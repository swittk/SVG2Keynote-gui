#ifndef KEYNOTE_PROTO_HELPER_H
#define KEYNOTE_PROTO_HELPER_H

#include <string>
#include <vector>

#include <google/protobuf/io/coded_stream.h>
#include <google/protobuf/message.h>

#include <KNArchives.pb.h>
#include <TSDArchives.pb.h>
#include <TSPArchiveMessages.pb.h>
#include <TSPMessages.pb.h>
#include <TSSArchives.pb.h>
#include <TSWPArchives.pb.h>
#include <nanosvg.h>

struct MessageWrapper {
    uint64_t identifier;
    uint32_t type;
    google::protobuf::Message *message;
    TSP::ArchiveInfo *archiveInfo;
};

std::string convertListOfMessagesToProtoStream(const std::vector<MessageWrapper *> &vector);
std::vector<MessageWrapper *> generateMetadataMessageList();
MessageWrapper *createMessageWrapper(
    google::protobuf::Message *message,
    google::protobuf::uint32 type,
    google::protobuf::uint64 identifier
);

#endif // KEYNOTE_PROTO_HELPER_H
