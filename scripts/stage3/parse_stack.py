import re
import parse_shared
RW = "(read|write)"
SB_STATE = "(Unique|SharedReadOnly|SharedReadWrite)"
STACK_ACTION_RW = re.compile(f"attempting a {RW} access using {parse_shared.TAG} at {parse_shared.ALLOCATION}")
STACK_ACTION_RETAG = re.compile(f"attempting to retag from {parse_shared.TAG} for {SB_STATE} permission at {parse_shared.ALLOCATION}")
STACK_ERROR_MISSING = re.compile(", but that tag does not exist")
STACK_ERROR_INSUFFICIENT = re.compile(f", but that tag only grants {SB_STATE}")
STACK_ERROR_DEALLOCATING = re.compile(f"deallocating while item \[{SB_STATE} for {parse_shared.TAG}\] is strongly protected by call")
CREATION_STACK = re.compile(f"{parse_shared.TAG} was created by a {SB_STATE} retag at offsets {parse_shared.OFFSETS}")
DESTRUCTION_STACK = re.compile(f"{parse_shared.TAG} was later invalidated at offsets {parse_shared.OFFSETS} by a {SB_STATE} (function-entry)? retag")
