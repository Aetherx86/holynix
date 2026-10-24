/*
 * HolyC Unix Kernel - Circular Ring Buffer (RingBuffer.HC)
 * Used for IPC pipes, terminal TTY queue, and kernel dmesg ring buffer.
 */

#ifndef RINGBUFFER_HC
#define RINGBUFFER_HC

#include "Types.HC"

class CRingBuffer {
    U8 *buf;
    I64 capacity;
    I64 head;
    I64 tail;
    I64 count;
    I64 ref_count;
};

CRingBuffer *RingBufCreate(I64 capacity) {
    if (capacity <= 0) capacity = 512;
    CRingBuffer *rb = (CRingBuffer*)MAlloc(sizeof(CRingBuffer));
    rb->buf = (U8*)MAlloc(capacity);
    rb->capacity = capacity;
    rb->head = 0;
    rb->tail = 0;
    rb->count = 0;
    rb->ref_count = 1;
    return rb;
}

U0 RingBufFree(CRingBuffer *rb) {
    if (rb) {
        if (rb->buf) Free(rb->buf);
        Free(rb);
    }
}

I64 RingBufAvail(CRingBuffer *rb) {
    if (!rb) return 0;
    return rb->count;
}

I64 RingBufSpace(CRingBuffer *rb) {
    if (!rb) return 0;
    return rb->capacity - rb->count;
}

I64 RingBufWrite(CRingBuffer *rb, const U8 *src, I64 len) {
    if (!rb || !src || len <= 0) return 0;
    I64 written = 0;
    while (written < len && rb->count < rb->capacity) {
        rb->buf[rb->head] = src[written++];
        rb->head = (rb->head + 1) % rb->capacity;
        rb->count++;
    }
    return written;
}

I64 RingBufRead(CRingBuffer *rb, U8 *dst, I64 len) {
    if (!rb || !dst || len <= 0) return 0;
    I64 nread = 0;
    while (nread < len && rb->count > 0) {
        dst[nread++] = rb->buf[rb->tail];
        rb->tail = (rb->tail + 1) % rb->capacity;
        rb->count--;
    }
    return nread;
}

U0 RingBufClear(CRingBuffer *rb) {
    if (rb) {
        rb->head = 0;
        rb->tail = 0;
        rb->count = 0;
    }
}

#endif /* RINGBUFFER_HC */
