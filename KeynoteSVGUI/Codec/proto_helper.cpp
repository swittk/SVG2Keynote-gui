#include "proto_helper.h"

#include <sstream>

std::string convertListOfMessagesToProtoStream(const std::vector<MessageWrapper *> &vector) {
    std::stringstream output;

    for (auto *message : vector) {
        message->archiveInfo->mutable_message_infos(0)->set_length(message->message->SerializeAsString().length());

        const std::string archiveInfoString = message->archiveInfo->SerializeAsString();
        const std::string messageString = message->message->SerializeAsString();
        const google::protobuf::uint64 size = archiveInfoString.length();
        const size_t varIntSize = google::protobuf::io::CodedOutputStream::VarintSize64(size);
        auto *varIntArr = new google::protobuf::uint8[varIntSize];
        google::protobuf::io::CodedOutputStream::WriteVarint64ToArray(size, varIntArr);
        output.write(reinterpret_cast<const char *>(varIntArr), static_cast<std::streamsize>(varIntSize));
        output << archiveInfoString;
        output << messageString;
        delete[] varIntArr;
    }

    return output.str();
}

std::vector<MessageWrapper *> generateMetadataMessageList() {
    auto *pasteboardMetadata = new TSP::PasteboardMetadata();
    pasteboardMetadata->add_version(11);
    pasteboardMetadata->add_version(1);
    pasteboardMetadata->add_version(2);
    pasteboardMetadata->set_allocated_app_name(new std::string("com.apple.Keynote 11.1"));
    pasteboardMetadata->add_read_version(2);
    pasteboardMetadata->add_read_version(0);
    pasteboardMetadata->add_read_version(0);

    return std::vector<MessageWrapper *>{createMessageWrapper(pasteboardMetadata, 11007, 52)};
}

MessageWrapper *createMessageWrapper(
    google::protobuf::Message *message,
    google::protobuf::uint32 type,
    google::protobuf::uint64 identifier
) {
    auto *messageWrapper = new MessageWrapper();
    auto *archiveInfo = new TSP::ArchiveInfo();
    auto *messageInfo = archiveInfo->add_message_infos();
    messageInfo->set_type(type);
    messageInfo->add_version(1);
    messageInfo->add_version(0);
    messageInfo->add_version(5);
    messageInfo->set_length(message->SerializeAsString().length());
    archiveInfo->set_identifier(identifier);

    messageWrapper->archiveInfo = archiveInfo;
    messageWrapper->identifier = identifier;
    messageWrapper->message = message;

    return messageWrapper;
}
