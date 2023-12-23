import re
import parse_shared
from enum import Enum
class SBOperation(Enum):
    read = "read"
    write = "write"
    retag = "retag"
    deallocating = "deallocating"

RW = f"({SBOperation.read.value}|{SBOperation.write.value})"

class SBState(Enum):
    Unique = "Unique"
    SharedReadOnly = "SharedReadOnly"
    SharedReadWrite = "SharedReadWrite"

class SBInvalidationType(Enum):
    Default = "Default"
    FunctionEntry = "FunctionEntry"
    CompoundValue = "CompoundValue"

class SBInvalidation:
    def __init__(self, action, permission, type = SBInvalidationType.Default):
        self.action = action
        self.permission = permission
        self.type = type
    def to_string(self):
        action = self.action.value if self.action is not None else "NA"
        permission = self.permission.value if self.permission is not None else "NA"
        type = self.type.value if self.type is not None else "NA"
        return f"{action},{permission},{type}"


SB_STATE = f"({SBState.Unique.value}|{SBState.SharedReadOnly.value}|{SBState.SharedReadWrite.value})"

STACK_ERROR_DEALLOCATING = re.compile(f"{SBOperation.deallocating.value} while item \[{SB_STATE} for {parse_shared.TAG}\] is strongly protected by call")
STACK_ACTION = re.compile(f"(?:attempting a {RW} access using {parse_shared.TAG_NC}|trying to retag from {parse_shared.TAG_NC} for {SB_STATE} permission) at {parse_shared.ALLOCATION}, but that tag (?:only grants {SB_STATE}|does not exist)?")
CREATION_STACK = re.compile(f"{parse_shared.TAG} was created by a {SB_STATE} retag")
DESTRUCTION_STACK = re.compile(f"{parse_shared.TAG} was later invalidated at offsets {parse_shared.OFFSETS} by a (?:{SB_STATE}( function-entry)? retag( \(of a reference/box)?|{RW} access)")
def parse_stack_subtype(action, help_text):
    print(help_text[0])

def stack_error(help_text):
    error_line = help_text[0]
    action_rw = STACK_ACTION.search(error_line)
    action_dealloc = STACK_ERROR_DEALLOCATING.search(error_line)
    protected = False
    action = None
    retag_target = None
    permission_limit = None
    invalidation = None
    start_permission = None
    if action_dealloc is not None:
        (state, tag) = action_dealloc.groups()
        action = SBOperation.deallocating
        start_permission = SBState[state]
        protected = True
    if action_rw is not None:
        (action, retag_target, permission_limit) = action_rw.groups()
        action = SBOperation[action] if action in SBOperation.__members__ else SBOperation.retag
        retag_target = SBState[retag_target] if retag_target in SBState.__members__ else None
        permission_limit = SBState[permission_limit] if permission_limit in SBState.__members__ else None
    if action_rw is not None or action_dealloc is not None:
        for line in help_text:
            if start_permission is None:
                creation = CREATION_STACK.search(line)
                if creation is not None:
                    (tag, retag_perm) = creation.groups()
                    if retag_perm is not None:
                        start_permission = SBState[retag_perm]
            if invalidation is None:
                destruction = DESTRUCTION_STACK.search(line)
                if destruction is not None:
                    (tag, retag_perm, function_entry, retag_of_comp, op) = destruction.groups()
                    inval_action = SBOperation[op] if op is not None else SBOperation.retag
                    retag_type = None
                    if retag_perm is not None:
                        retag_type = SBInvalidationType.Default
                        retag_perm = SBState[retag_perm]
                        if function_entry is not None:
                            retag_type = SBInvalidationType.FunctionEntry
                        elif retag_of_comp is not None:
                            retag_type = SBInvalidationType.CompoundValue
                    invalidation = SBInvalidation(inval_action, retag_perm, retag_type)
        error = SBError(action, start_permission, retag_target, permission_limit, protected, invalidation)
        return error.summarize()

class SBError:
    def __init__(self, action = None, retag_target = None, permission = None, limit = None, protected = False, invalidation = None):
        self.action = action
        self.retag_target = retag_target
        self.permission = permission
        self.limit = limit
        self.invalidation = invalidation
        self.protected = protected
    def to_string(self):
        action = self.action.value if self.action is not None else "NA"
        permission = self.permission.value if self.permission is not None else "NA"
        limit = self.limit.value if self.limit is not None else "NA"
        invalidation = self.invalidation.to_string() if self.invalidation is not None else "NA"
        retag_target = self.retag_target.value if self.retag_target is not None else "NA"
        protected = "TRUE" if self.protected else "FALSE"
        return f"{action},{permission},{retag_target},{limit},{invalidation},{protected}"
    def summarize(self):
        error_type = None
        if self.protected:
            error_type = SBErrorType.Protected
        if self.limit is not None:
            if self.limit == SBState.SharedReadOnly and self.action is not None:
                error_type = SBErrorType.Insufficient
        else:
            if self.invalidation is None:
                error_type = SBErrorType.OutOfBounds
            else:
                if self.invalidation.action == SBOperation.retag:
                    if self.invalidation.permission == SBState.Unique:
                        error_type = SBErrorType.InvalidatedByUniqueRetag  
                elif self.invalidation.action == SBOperation.write:
                    error_type = SBErrorType.InvalidatedByWrite
                if self.invalidation.action == SBOperation.read:
                    error_type = SBErrorType.InvalidatedByRead

        if self.action is None or error_type is None:
            print("Unrecognized Stacked Borrows error type: ", self.to_string())
            exit(1)
        return [self.action.value, error_type.value]
class SBErrorType(Enum):
    Insufficient = "Insufficient"
    OutOfBounds = "OutOfBounds"
    InvalidatedByUniqueRetag = "InvalidatedByUniqueRetag"
    InvalidatedByRead = "InvalidatedByRead"
    InvalidatedByWrite = "InvalidatedByWrite"
    Protected = "Protected"