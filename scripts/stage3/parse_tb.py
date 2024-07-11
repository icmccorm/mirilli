import re
import parse_shared
from enum import Enum
from parse_shared import Operation

TB_COLUMNS = ["action", "kind"]
TB_ACTION = f"({Operation.read.value}|{Operation.write.value}|{Operation.retag.value}|{Operation.dealloc.value})(?:ation)?(?: access)?"

class TBHierarchy(Enum):
    foreign = "foreign"
    child = "child"


TB_HIERARCHY = f"({TBHierarchy.foreign.value}|{TBHierarchy.child.value})"


class TBRole(Enum):
    accessed = "accessed"
    conflicting = "conflicting"
    protected = "protected"
    strongly_protected = "strongly protected"


TB_REFERRENT = f"({TBRole.accessed.value}|{TBRole.conflicting.value}|{TBRole.protected.value}|{TBRole.strongly_protected.value})"


class TBState(Enum):
    Frozen = "Frozen"
    Disabled = "Disabled"
    Active = "Active"
    Reserved = "Reserved"


TB_STATE = f"({TBState.Frozen.value}|{TBState.Disabled.value}|{TBState.Active.value}|{TBState.Reserved.value})"

TB_ERROR = re.compile(f"{TB_ACTION} through {parse_shared.TAG} is forbidden")
RELATION_TREE = re.compile(
    f"the accessed tag {parse_shared.TAG} is a child of the {TB_REFERRENT} tag {parse_shared.TAG}"
)
CREATION_TREE = re.compile(
    f"\s*the {TB_REFERRENT} tag {parse_shared.TAG} was created here(?:, in the initial state {TB_STATE})*\s*"
)
DESTRUCTION_TREE = re.compile(
    f"\s*the {TB_REFERRENT} tag {parse_shared.TAG} later transitioned to {TB_STATE} due to a (?:{TB_HIERARCHY} {TB_ACTION}|reborrow \(acting as a {TB_HIERARCHY} {TB_ACTION}\)) at offsets {parse_shared.OFFSETS}\s*"
)


class TBAction:
    def __init__(self, action, relation):
        self.action = action
        self.relation = relation

    def exists(self):
        return self.action is not None and self.relation is not None

    def to_string(self):
        action = self.action.value if self.action is not None else "NA"
        relation = self.relation.value if self.relation is not None else "NA"
        return f"{action},{relation}"


class TBTagTransition:
    def __init__(self, kind, action=None, start_state=None, end_state=None):
        self.kind = kind
        self.action = action
        self.start_state = start_state
        self.end_state = end_state

    def to_string(self):
        kind = self.kind.value if self.kind is not None else "NA"
        start_state = self.start_state.value if self.start_state is not None else "NA"
        end_state = self.end_state.value if self.end_state is not None else "NA"
        action = self.action.to_string() if self.action is not None else "NA"
        return f"{kind},{start_state},{end_state},{action}"

    def exists(self):
        return (
            self.action.exists()
            and self.start_state is not None
            and self.end_state is not None
            and self.kind is not None
        )


class TBError:
    def __init__(
        self, action_type, is_child, accessed_tag_transition, conflicting_tag_transition
    ):
        self.accessed_tag_transition = accessed_tag_transition
        self.conflicting_tag_transition = conflicting_tag_transition
        self.action_type = action_type
        self.is_child = is_child

    def summarize(self):
        error_type = None
        indirection_type = (
            TBErrorIndirectionType.Direct
            if self.is_child
            else TBErrorIndirectionType.Indirect
        )
        if self.accessed_tag_transition.exists():
            if disabled_by(foreign_write, self.accessed_tag_transition):
                error_type = TBErrorTypeWithIndirection(
                    TBErrorType.Expired, indirection_type
                ).to_string()
        elif self.conflicting_tag_transition.exists():
            if disabled_by(foreign_write, self.conflicting_tag_transition):
                error_type = TBErrorTypeWithIndirection(
                    TBErrorType.Expired, indirection_type
                ).to_string()
            if frozen_by(foreign_read, self.conflicting_tag_transition):
                error_type = TBErrorTypeWithIndirection(
                    TBErrorType.Insufficient, indirection_type
                ).to_string()
        else:
            if (
                self.conflicting_tag_transition.kind == TBRole.protected
                or self.conflicting_tag_transition.kind == TBRole.strongly_protected
            ):
                error_type = TBErrorType.Framing.value
            if (
                self.action_type == Operation.write
                or self.action_type == Operation.dealloc
            ):
                if self.accessed_tag_transition.start_state == TBState.Frozen:
                    error_type = TBErrorTypeWithIndirection(
                        TBErrorType.Insufficient, indirection_type
                    ).to_string()
                elif self.conflicting_tag_transition.start_state == TBState.Frozen:
                    error_type = TBErrorTypeWithIndirection(
                        TBErrorType.Insufficient, indirection_type
                    ).to_string()
        if self.action_type is None or error_type is None or indirection_type is None:
            print("Unrecognized Tree Borrows error type")
            exit(1)
        return [self.action_type.value, error_type]


class TBErrorTypeWithIndirection:
    def __init__(self, error_type, indirection):
        self.indirection = indirection
        self.error_type = error_type

    def to_string(self):
        error_type = self.error_type.value
        indirection = self.indirection.value if self.indirection is not None else "NA"
        return f"{error_type}-{indirection}"


class TBErrorIndirectionType(Enum):
    Indirect = "Indirect"
    Direct = "Direct"


class TBErrorType(Enum):
    Expired = "Expired"
    Insufficient = "Insufficient"
    Framing = "Framing"


def foreign_write(tb_action):
    return (
        tb_action.action == Operation.write
        and tb_action.relation == TBHierarchy.foreign
    )


def foreign_read(tb_action):
    return (
        tb_action.action == Operation.read
        and tb_action.relation == TBHierarchy.foreign
    )


def child_write(tb_action):
    return (
        tb_action.action == Operation.write
        and tb_action.relation == TBHierarchy.child
    )


def child_read(tb_action):
    return (
        tb_action.action == Operation.read and tb_action.relation == TBHierarchy.child
    )


def disabled_by(tb_reason, tb_transition):
    return (
        tb_reason(tb_transition.action) and tb_transition.end_state == TBState.Disabled
    )


def frozen_by(tb_reason, tb_transition):
    return tb_reason(tb_transition.action) and tb_transition.end_state == TBState.Frozen


def parse_tb_subtype(action, help_text):
    access_type = None

    accessed_child = None
    accessed_creation = None
    accessed_destruction = None
    accessed_destruction_type = None
    accessed_destruction_relation = None

    conflicting_kind = None
    conflicting_creation = None
    conflicting_destruction = None
    conflicting_destruction_type = None
    conflicting_destruction_relation = None

    info_text = ""

    for line in help_text:
        creation = CREATION_TREE.search(line)
        destruction = DESTRUCTION_TREE.search(line)
        if access_type is None:
            error = TB_ERROR.search(line)
            if error is not None:
                info_text += "Error: " + str(error.groups()) + "\n"
                access_type = Operation[action]
                continue
        if accessed_child is None:
            relation = RELATION_TREE.search(line)
            if relation is not None:
                info_text += "Relation: " + str(relation.groups()) + "\n"
                accessed_child = relation.groups()
                continue
        if creation is not None:
            info_text += "Creation: " + str(creation.groups()) + "\n"
            (referrent, tag, state) = creation.groups()
            if state is not None:
                if referrent == TBRole.accessed.value:
                    accessed_creation = TBState[state]
                else:
                    conflicting_kind = TBRole[referrent.replace(" ", "_")]
                    conflicting_creation = TBState[state]
                continue
        elif destruction is not None:
            info_text += "Destruction: " + str(destruction.groups()) + "\n"
            (
                referrent,
                tag,
                result_state,
                action_relation,
                action_type,
                retag_action_relation,
                retag_action_type,
            ) = destruction.groups()
            action_relation = (
                action_relation
                if action_relation is not None
                else retag_action_relation
            )
            action_type = action_type if action_type is not None else retag_action_type
            if referrent == TBRole.accessed.value:
                accessed_destruction_relation = TBHierarchy[action_relation]
                accessed_destruction_type = Operation[action_type]
                accessed_destruction = TBState[result_state]
            else:
                conflicting_destruction_relation = TBHierarchy[action_relation]
                conflicting_destruction_type = Operation[action_type]
                conflicting_destruction = TBState[result_state]
            continue

    access_action = TBAction(accessed_destruction_type, accessed_destruction_relation)
    conflicting_action = TBAction(
        conflicting_destruction_type, conflicting_destruction_relation
    )
    accessed_transition = TBTagTransition(
        kind=TBRole.accessed,
        action=access_action,
        start_state=accessed_creation,
        end_state=accessed_destruction,
    )
    conflicting_transition = TBTagTransition(
        kind=conflicting_kind,
        action=conflicting_action,
        start_state=conflicting_creation,
        end_state=conflicting_destruction,
    )
    tb_error = TBError(
        access_type,
        accessed_child is not None,
        accessed_transition,
        conflicting_transition,
    )
    return tb_error.summarize()

def tb_error(help_text):
    error_text = help_text[0]
    match = TB_ERROR.search(error_text)
    if match is not None:
        (action, accessed_tag) = match.group(1, 2)
        return parse_tb_subtype(action, help_text)
