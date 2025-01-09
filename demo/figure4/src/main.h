struct Stream;
typedef struct {
    struct Stream * parent;
} State;

typedef struct {
    int data;
    State * child;
} Stream;

void init(Stream *stream);
void compress(Stream *stream);

// this function was left out of the example
// provided in-text, since it is not relevant
// to the UB. It is called as part of the implementation
// of Drop for the Rust encapsulation of Stream.
void drop(Stream *s);