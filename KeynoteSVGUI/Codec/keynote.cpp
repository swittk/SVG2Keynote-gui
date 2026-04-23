#include "keynote.hpp"
#include "proto_helper.h"
#include "src/svg_to_key/svg_to_key.h"

std::string generateTSPNativeDataClipboardFromSVG(const std::string &svgContents) {
    std::vector<MessageWrapper *> objects = *convertSVGFileToKeynoteClipboard(svgContents);
    return convertListOfMessagesToProtoStream(objects);
}

std::string generateTSPNativeMetadataClipboard() {
    auto metadataMessageList = generateMetadataMessageList();
    return convertListOfMessagesToProtoStream(metadataMessageList);
}
