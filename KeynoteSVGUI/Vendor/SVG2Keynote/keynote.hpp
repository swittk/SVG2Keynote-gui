#ifndef SVG2KEYNOTE_KEYNOTE_HPP
#define SVG2KEYNOTE_KEYNOTE_HPP

#include <string>

std::string generateTSPNativeDataClipboardFromSVG(const std::string &svgContents);
std::string generateTSPNativeMetadataClipboard();

#endif // SVG2KEYNOTE_KEYNOTE_HPP
