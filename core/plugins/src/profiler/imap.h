#ifndef _IMAP_H_
#define _IMAP_H_


#ifndef WIN32
#include <unistd.h>
#endif // !WIN32
#include <stdint.h>
struct imap_context;


struct imap_context* imap_create();
void imap_free(struct imap_context* imap);

// the value is no-null point
void imap_set(struct imap_context* imap, uint64_t key, void* value);

void* imap_remove(struct imap_context* imap, uint64_t key);
void* imap_query(struct imap_context* imap, uint64_t key);

typedef void(*observer)(uint64_t key, void* value, void* ud);
void imap_dump(struct imap_context* imap, observer observer_cb, void* ud);

#endif
