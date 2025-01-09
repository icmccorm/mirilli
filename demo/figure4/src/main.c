#include <stdlib.h>
struct Stream;
typedef struct
{
    struct Stream *stream;
} State;

typedef struct
{
    int data;
    State *state;
} Stream;

void init(Stream *s)
{
    s->state = malloc(sizeof(State));
    //We excluded the cast to `Stream *` in the original presentation for brevity.
    s->state->stream = (struct Stream *) s;
}

void compress(Stream *s)
{
    //We excluded the cast to `Stream *` in the original presentation for brevity.
    int data = ((Stream *)s->state->stream)->data;
}

void drop_stream(Stream *s)
{
    free(s->state);
}
