import re
from enum import Enum

TAG_NC = "<(?:[0-9]*|wildcard)>"
OFFSETS = "\[0x[0-9a-f]+\.\.0x[0-9a-f]+\]"
TAG = "<([0-9]*|wildcard)>"
ALLOCATION = "alloc[0-9]*\[0x[0-9a-f]+\]"
COLUMNS = ["action", "kind"]
RE_MAYBEUNINIT = re.compile(
    r"(error): .*\n.  --> .*\n(?:    \|\n)*([0-9]+[ ]+\|.* )(:?(:?std::){0,1}mem::){0,1}(MaybeUninit::uninit\(\).assume_init\(\))"
)
RE_MEM_UNINIT = re.compile(
    r"(error): .*\n.  --> .*\n(?:    \|\n)*([0-9]+[ ]+\|.* )(:?(:?std::){0,1}mem::){0,1}(uninitialized\(\))"
)

class Operation(Enum):
    read = "read"
    write = "write"
    retag = "retag"
    dealloc = "dealloc"