from enum import Enum
import re
TAG_NC="<[0-9]*>"
OFFSETS = "\[0x[0-9a-f]+\.\.0x[0-9a-f]+\]"
TAG="<([0-9]*)>"
ALLOCATION="alloc[0-9]*\[0x[0-9a-f]+\]"
COLUMNS = ["action", "kind", "subkind"]
RE_MAYBEUNINIT = re.compile(r"(error): .*\n.  --> .*\n(?:    \|\n)*([0-9]+[ ]+\|.* )(:?(:?std::){0,1}mem::){0,1}(MaybeUninit::uninit\(\).assume_init\(\))")
RE_MEM_UNINIT = re.compile(r"(error): .*\n.  --> .*\n(?:    \|\n)*([0-9]+[ ]+\|.* )(:?(:?std::){0,1}mem::){0,1}(uninitialized\(\))")