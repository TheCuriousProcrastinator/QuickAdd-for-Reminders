#ifndef RichLinkBridge_h
#define RichLinkBridge_h

int add_rich_link_to_existing_reminder(
    const char *listIDCString,
    const char *externalIdentifierCString,
    const char *urlCString,
    char *errorBuffer,
    int errorBufferLength
);

#endif
