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
    s->state->stream = s;
}

void compress(Stream *s)
{
    int data = ((Stream *)s->state->stream)->data;
}

void drop(Stream *s)
{
    free(s->state);
}