#include "keynote.hpp"
#include "proto_helper.h"
#include "src/svg_to_key/svg_to_key.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kEpsilon = 1e-6;

struct SerializedMessage {
    google::protobuf::uint32 type = 0;
    google::protobuf::uint64 identifier = 0;
    std::string payload;
};

struct AffineTransform {
    double a = 1.0;
    double b = 0.0;
    double c = 0.0;
    double d = 1.0;
    double e = 0.0;
    double f = 0.0;
};

struct Bounds {
    double minX = std::numeric_limits<double>::infinity();
    double minY = std::numeric_limits<double>::infinity();
    double maxX = -std::numeric_limits<double>::infinity();
    double maxY = -std::numeric_limits<double>::infinity();

    void include(double x, double y) {
        minX = std::min(minX, x);
        minY = std::min(minY, y);
        maxX = std::max(maxX, x);
        maxY = std::max(maxY, y);
    }

    bool isValid() const {
        return std::isfinite(minX) && std::isfinite(minY) && std::isfinite(maxX) && std::isfinite(maxY) &&
               maxX >= minX && maxY >= minY;
    }
};

struct ExportedStyle {
    std::string fillValue = "#000000";
    bool fillNone = false;
    double fillOpacity = 1.0;
    std::string strokeValue = "none";
    bool hasStroke = false;
    double strokeOpacity = 1.0;
    double strokeWidth = 0.0;
    std::string lineCap;
    std::string lineJoin;
    double miterLimit = 0.0;
    std::vector<double> dashArray;
    double opacity = 1.0;
};

struct ExportedShape {
    std::string pathData;
    ExportedStyle style;
    AffineTransform transform;
    Bounds bounds;
};

using SerializedMessageMap = std::unordered_map<google::protobuf::uint64, SerializedMessage>;

std::string formatFloat(double value) {
    if (!std::isfinite(value) || std::abs(value) < kEpsilon) {
        value = 0.0;
    }

    std::ostringstream stream;
    stream << std::fixed << std::setprecision(6) << value;
    std::string result = stream.str();

    while (!result.empty() && result.back() == '0') {
        result.pop_back();
    }
    if (!result.empty() && result.back() == '.') {
        result.pop_back();
    }
    if (result == "-0") {
        return "0";
    }
    return result.empty() ? "0" : result;
}

std::string escapeXML(const std::string &value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (char character : value) {
        switch (character) {
            case '&':
                escaped += "&amp;";
                break;
            case '"':
                escaped += "&quot;";
                break;
            case '\'':
                escaped += "&apos;";
                break;
            case '<':
                escaped += "&lt;";
                break;
            case '>':
                escaped += "&gt;";
                break;
            default:
                escaped.push_back(character);
                break;
        }
    }
    return escaped;
}

int clampColorComponent(double component) {
    const double clamped = std::max(0.0, std::min(1.0, component));
    return static_cast<int>(std::lround(clamped * 255.0));
}

std::string colorToHex(const TSP::Color &color) {
    std::ostringstream stream;
    stream << '#'
           << std::hex << std::setfill('0') << std::nouppercase
           << std::setw(2) << clampColorComponent(color.r())
           << std::setw(2) << clampColorComponent(color.g())
           << std::setw(2) << clampColorComponent(color.b());
    return stream.str();
}

double colorOpacity(const TSP::Color &color) {
    if (!color.has_a()) {
        return 1.0;
    }
    return std::max(0.0, std::min(1.0, static_cast<double>(color.a())));
}

std::string strokeLineCapToSVG(TSD::StrokeArchive_LineCap cap) {
    switch (cap) {
        case TSD::StrokeArchive_LineCap_RoundCap:
            return "round";
        case TSD::StrokeArchive_LineCap_SquareCap:
            return "square";
        case TSD::StrokeArchive_LineCap_ButtCap:
        default:
            return "butt";
    }
}

std::string lineJoinToSVG(TSD::LineJoin join) {
    switch (join) {
        case TSD::RoundJoin:
            return "round";
        case TSD::BevelJoin:
            return "bevel";
        case TSD::MiterJoin:
        default:
            return "miter";
    }
}

AffineTransform multiply(const AffineTransform &lhs, const AffineTransform &rhs) {
    AffineTransform result;
    result.a = lhs.a * rhs.a + lhs.c * rhs.b;
    result.b = lhs.b * rhs.a + lhs.d * rhs.b;
    result.c = lhs.a * rhs.c + lhs.c * rhs.d;
    result.d = lhs.b * rhs.c + lhs.d * rhs.d;
    result.e = lhs.a * rhs.e + lhs.c * rhs.f + lhs.e;
    result.f = lhs.b * rhs.e + lhs.d * rhs.f + lhs.f;
    return result;
}

AffineTransform makeTranslation(double tx, double ty) {
    AffineTransform transform;
    transform.e = tx;
    transform.f = ty;
    return transform;
}

AffineTransform makeScale(double sx, double sy) {
    AffineTransform transform;
    transform.a = sx;
    transform.d = sy;
    return transform;
}

AffineTransform makeRotationDegrees(double angleDegrees) {
    const double radians = angleDegrees * kPi / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);

    AffineTransform transform;
    transform.a = cosine;
    transform.b = sine;
    transform.c = -sine;
    transform.d = cosine;
    return transform;
}

AffineTransform makeRotationAround(double angleDegrees, double cx, double cy) {
    return multiply(
        makeTranslation(cx, cy),
        multiply(makeRotationDegrees(angleDegrees), makeTranslation(-cx, -cy))
    );
}

AffineTransform makeHorizontalFlip(double width) {
    return multiply(makeTranslation(width, 0.0), makeScale(-1.0, 1.0));
}

AffineTransform makeVerticalFlip(double height) {
    return multiply(makeTranslation(0.0, height), makeScale(1.0, -1.0));
}

std::pair<double, double> applyTransform(const AffineTransform &transform, double x, double y) {
    return {
        transform.a * x + transform.c * y + transform.e,
        transform.b * x + transform.d * y + transform.f,
    };
}

Bounds transformedRectBounds(const AffineTransform &transform, double width, double height) {
    Bounds bounds;
    const std::pair<double, double> points[] = {
        applyTransform(transform, 0.0, 0.0),
        applyTransform(transform, width, 0.0),
        applyTransform(transform, 0.0, height),
        applyTransform(transform, width, height),
    };
    for (const auto &point : points) {
        bounds.include(point.first, point.second);
    }
    return bounds;
}

AffineTransform transformForGeometry(const TSD::GeometryArchive &geometry,
                                     double naturalWidth,
                                     double naturalHeight,
                                     bool horizontalFlip,
                                     bool verticalFlip) {
    double width = naturalWidth > kEpsilon ? naturalWidth : 1.0;
    double height = naturalHeight > kEpsilon ? naturalHeight : 1.0;

    if (geometry.has_size()) {
        if (geometry.size().width() > kEpsilon) {
            width = geometry.size().width();
        }
        if (geometry.size().height() > kEpsilon) {
            height = geometry.size().height();
        }
    }

    const double scaleX = naturalWidth > kEpsilon ? width / naturalWidth : 1.0;
    const double scaleY = naturalHeight > kEpsilon ? height / naturalHeight : 1.0;

    AffineTransform transform = makeScale(scaleX, scaleY);

    if (horizontalFlip) {
        transform = multiply(makeHorizontalFlip(width), transform);
    }
    if (verticalFlip) {
        transform = multiply(makeVerticalFlip(height), transform);
    }
    if (geometry.has_angle() && std::abs(geometry.angle()) > kEpsilon) {
        transform = multiply(makeRotationAround(geometry.angle(), width * 0.5, height * 0.5), transform);
    }
    if (geometry.has_position()) {
        transform = multiply(makeTranslation(geometry.position().x(), geometry.position().y()), transform);
    }

    return transform;
}

const TSP::Point &nodeControlPointOrNode(const TSD::EditableBezierPathSourceArchive_Node &node,
                                         bool useOutControl) {
    if (useOutControl && node.has_outcontrolpoint()) {
        return node.outcontrolpoint();
    }
    if (!useOutControl && node.has_incontrolpoint()) {
        return node.incontrolpoint();
    }
    return node.nodepoint();
}

void appendCoordinatePair(std::ostringstream &stream, double x, double y) {
    stream << formatFloat(x) << ' ' << formatFloat(y);
}

std::string pathDataFromPath(const TSP::Path &path) {
    std::ostringstream stream;

    for (const auto &element : path.elements()) {
        switch (element.type()) {
            case TSP::Path_ElementType_moveTo:
                if (element.points_size() >= 1) {
                    stream << 'M' << ' ';
                    appendCoordinatePair(stream, element.points(0).x(), element.points(0).y());
                    stream << ' ';
                }
                break;
            case TSP::Path_ElementType_lineTo:
                if (element.points_size() >= 1) {
                    stream << 'L' << ' ';
                    for (int index = 0; index < element.points_size(); ++index) {
                        if (index > 0) {
                            stream << ' ';
                        }
                        appendCoordinatePair(stream, element.points(index).x(), element.points(index).y());
                    }
                    stream << ' ';
                }
                break;
            case TSP::Path_ElementType_quadCurveTo:
                if (element.points_size() >= 2) {
                    stream << 'Q' << ' ';
                    appendCoordinatePair(stream, element.points(0).x(), element.points(0).y());
                    stream << ' ';
                    appendCoordinatePair(stream, element.points(1).x(), element.points(1).y());
                    stream << ' ';
                }
                break;
            case TSP::Path_ElementType_curveTo:
                if (element.points_size() >= 3) {
                    stream << 'C' << ' ';
                    appendCoordinatePair(stream, element.points(0).x(), element.points(0).y());
                    stream << ' ';
                    appendCoordinatePair(stream, element.points(1).x(), element.points(1).y());
                    stream << ' ';
                    appendCoordinatePair(stream, element.points(2).x(), element.points(2).y());
                    stream << ' ';
                }
                break;
            case TSP::Path_ElementType_closeSubpath:
                stream << 'Z' << ' ';
                break;
            default:
                break;
        }
    }

    return stream.str();
}

void appendEditableBezierCurve(std::ostringstream &stream,
                               const TSD::EditableBezierPathSourceArchive_Node &fromNode,
                               const TSD::EditableBezierPathSourceArchive_Node &toNode) {
    const TSP::Point &outControl = nodeControlPointOrNode(fromNode, true);
    const TSP::Point &inControl = nodeControlPointOrNode(toNode, false);
    const TSP::Point &destination = toNode.nodepoint();

    stream << 'C' << ' ';
    appendCoordinatePair(stream, outControl.x(), outControl.y());
    stream << ' ';
    appendCoordinatePair(stream, inControl.x(), inControl.y());
    stream << ' ';
    appendCoordinatePair(stream, destination.x(), destination.y());
    stream << ' ';
}

std::string pathDataFromEditablePath(const TSD::EditableBezierPathSourceArchive &editablePath) {
    std::ostringstream stream;

    for (const auto &subpath : editablePath.subpaths()) {
        if (subpath.nodes_size() == 0 || !subpath.nodes(0).has_nodepoint()) {
            continue;
        }

        const TSD::EditableBezierPathSourceArchive_Node &firstNode = subpath.nodes(0);
        stream << 'M' << ' ';
        appendCoordinatePair(stream, firstNode.nodepoint().x(), firstNode.nodepoint().y());
        stream << ' ';

        for (int index = 1; index < subpath.nodes_size(); ++index) {
            const TSD::EditableBezierPathSourceArchive_Node &previousNode = subpath.nodes(index - 1);
            const TSD::EditableBezierPathSourceArchive_Node &currentNode = subpath.nodes(index);
            if (!currentNode.has_nodepoint()) {
                continue;
            }
            appendEditableBezierCurve(stream, previousNode, currentNode);
        }

        if (subpath.closed() && subpath.nodes_size() > 1) {
            const TSD::EditableBezierPathSourceArchive_Node &lastNode = subpath.nodes(subpath.nodes_size() - 1);
            appendEditableBezierCurve(stream, lastNode, firstNode);
            stream << 'Z' << ' ';
        }
    }

    return stream.str();
}

bool parseClipboardMessageStream(const std::string &clipboardData, SerializedMessageMap *messages) {
    if (messages == nullptr || clipboardData.empty()) {
        return false;
    }

    google::protobuf::io::CodedInputStream stream(
        reinterpret_cast<const google::protobuf::uint8 *>(clipboardData.data()),
        static_cast<int>(clipboardData.size())
    );

    while (stream.CurrentPosition() < static_cast<int>(clipboardData.size())) {
        google::protobuf::uint64 archiveInfoSize = 0;
        if (!stream.ReadVarint64(&archiveInfoSize)) {
            break;
        }

        if (archiveInfoSize == 0 || archiveInfoSize > static_cast<google::protobuf::uint64>(clipboardData.size())) {
            return !messages->empty();
        }

        TSP::ArchiveInfo archiveInfo;
        const auto archiveLimit = stream.PushLimit(static_cast<int>(archiveInfoSize));
        const bool parsedArchiveInfo = archiveInfo.ParseFromCodedStream(&stream);
        stream.PopLimit(archiveLimit);
        if (!parsedArchiveInfo || archiveInfo.message_infos_size() == 0) {
            return !messages->empty();
        }

        const TSP::MessageInfo &messageInfo = archiveInfo.message_infos(0);
        const int payloadLength = messageInfo.length();
        if (payloadLength < 0) {
            return !messages->empty();
        }

        SerializedMessage serializedMessage;
        serializedMessage.type = messageInfo.type();
        serializedMessage.identifier = archiveInfo.identifier();
        serializedMessage.payload.resize(static_cast<size_t>(payloadLength));
        if (payloadLength > 0 && !stream.ReadRaw(serializedMessage.payload.data(), payloadLength)) {
            return !messages->empty();
        }

        (*messages)[serializedMessage.identifier] = std::move(serializedMessage);
    }

    return !messages->empty();
}

bool parsePasteboardObject(const SerializedMessageMap &messages, TSP::PasteboardObject *pasteboardObject) {
    if (pasteboardObject == nullptr) {
        return false;
    }

    for (const auto &pair : messages) {
        if (pair.second.type != 11000) {
            continue;
        }
        return pasteboardObject->ParseFromString(pair.second.payload);
    }

    return false;
}

bool parseStyleReference(const SerializedMessageMap &messages,
                         google::protobuf::uint64 styleIdentifier,
                         std::vector<std::string> *definitions,
                         size_t *gradientCounter,
                         ExportedStyle *style) {
    if (style == nullptr) {
        return false;
    }

    const auto iterator = messages.find(styleIdentifier);
    if (iterator == messages.end()) {
        return false;
    }

    TSD::ShapeStyleArchive shapeStyleArchive;
    if (iterator->second.type == 2025) {
        TSWP::ShapeStyleArchive wrappedStyleArchive;
        if (!wrappedStyleArchive.ParseFromString(iterator->second.payload) || !wrappedStyleArchive.has_super()) {
            return false;
        }
        shapeStyleArchive = wrappedStyleArchive.super();
    } else if (iterator->second.type == 3015) {
        if (!shapeStyleArchive.ParseFromString(iterator->second.payload)) {
            return false;
        }
    } else {
        return false;
    }

    if (!shapeStyleArchive.has_shape_properties()) {
        return false;
    }

    const TSD::ShapeStylePropertiesArchive &shapeProperties = shapeStyleArchive.shape_properties();
    style->opacity = shapeProperties.has_opacity() ? shapeProperties.opacity() : 1.0;

    if (shapeProperties.has_fill()) {
        const TSD::FillArchive &fill = shapeProperties.fill();
        if (fill.has_color()) {
            const double alpha = colorOpacity(fill.color());
            style->fillNone = alpha <= kEpsilon;
            style->fillValue = style->fillNone ? "none" : colorToHex(fill.color());
            style->fillOpacity = alpha;
        } else if (fill.has_gradient() && fill.gradient().stops_size() > 0) {
            const TSD::GradientArchive &gradient = fill.gradient();
            if (gradient.type() == TSD::GradientArchive_GradientType_Linear && definitions != nullptr && gradientCounter != nullptr) {
                const std::string gradientIdentifier = "gradient-" + std::to_string((*gradientCounter)++);
                std::ostringstream definition;
                definition << "<linearGradient id=\"" << escapeXML(gradientIdentifier) << "\" gradientUnits=\"userSpaceOnUse\"";
                if (gradient.has_transformgradient()) {
                    const TSD::TransformGradientArchive &transformGradient = gradient.transformgradient();
                    if (transformGradient.has_start()) {
                        definition << " x1=\"" << formatFloat(transformGradient.start().x()) << "\""
                                   << " y1=\"" << formatFloat(transformGradient.start().y()) << "\"";
                    }
                    if (transformGradient.has_end()) {
                        definition << " x2=\"" << formatFloat(transformGradient.end().x()) << "\""
                                   << " y2=\"" << formatFloat(transformGradient.end().y()) << "\"";
                    }
                }
                definition << ">";
                for (const auto &stop : gradient.stops()) {
                    if (!stop.has_color()) {
                        continue;
                    }
                    definition << "<stop offset=\"" << formatFloat(stop.fraction() * 100.0) << "%\""
                               << " stop-color=\"" << colorToHex(stop.color()) << "\"";
                    const double stopOpacity = colorOpacity(stop.color());
                    if (stopOpacity < 1.0 - kEpsilon) {
                        definition << " stop-opacity=\"" << formatFloat(stopOpacity) << "\"";
                    }
                    definition << " />";
                }
                definition << "</linearGradient>";
                definitions->push_back(definition.str());
                style->fillNone = false;
                style->fillValue = "url(#" + gradientIdentifier + ")";
                style->fillOpacity = 1.0;
            } else {
                const TSD::GradientArchive_GradientStop &firstStop = gradient.stops(0);
                if (firstStop.has_color()) {
                    const double alpha = colorOpacity(firstStop.color());
                    style->fillNone = alpha <= kEpsilon;
                    style->fillValue = style->fillNone ? "none" : colorToHex(firstStop.color());
                    style->fillOpacity = alpha;
                }
            }
        }
    }

    if (shapeProperties.has_stroke()) {
        const TSD::StrokeArchive &stroke = shapeProperties.stroke();
        if (stroke.has_color() && stroke.width() > kEpsilon) {
            const double alpha = colorOpacity(stroke.color());
            style->hasStroke = alpha > kEpsilon;
            style->strokeValue = style->hasStroke ? colorToHex(stroke.color()) : "none";
            style->strokeOpacity = alpha;
            style->strokeWidth = stroke.width();
            if (stroke.has_cap()) {
                style->lineCap = strokeLineCapToSVG(stroke.cap());
            }
            if (stroke.has_join()) {
                style->lineJoin = lineJoinToSVG(stroke.join());
            }
            if (stroke.has_miter_limit()) {
                style->miterLimit = stroke.miter_limit();
            }
            if (stroke.has_pattern()) {
                for (float dashLength : stroke.pattern().pattern()) {
                    if (dashLength > kEpsilon) {
                        style->dashArray.push_back(dashLength);
                    }
                }
            }
        }
    }

    return true;
}

bool collectDrawable(const SerializedMessageMap &messages,
                     google::protobuf::uint64 identifier,
                     const AffineTransform &parentTransform,
                     std::unordered_set<google::protobuf::uint64> *visitedIdentifiers,
                     std::vector<std::string> *definitions,
                     size_t *gradientCounter,
                     std::vector<ExportedShape> *shapes);

bool collectShapeArchive(const SerializedMessageMap &messages,
                         const TSD::ShapeArchive &shapeArchive,
                         const AffineTransform &parentTransform,
                         std::vector<std::string> *definitions,
                         size_t *gradientCounter,
                         std::vector<ExportedShape> *shapes) {
    if (!shapeArchive.has_super() || !shapeArchive.super().has_geometry() || !shapeArchive.has_pathsource()) {
        return false;
    }

    const TSD::DrawableArchive &drawableArchive = shapeArchive.super();
    const TSD::PathSourceArchive &pathSource = shapeArchive.pathsource();

    std::string pathData;
    double naturalWidth = drawableArchive.geometry().has_size() ? drawableArchive.geometry().size().width() : 1.0;
    double naturalHeight = drawableArchive.geometry().has_size() ? drawableArchive.geometry().size().height() : 1.0;

    if (pathSource.has_bezier_path_source()) {
        const TSD::BezierPathSourceArchive &bezierPath = pathSource.bezier_path_source();
        if (!bezierPath.has_path()) {
            return false;
        }
        if (bezierPath.has_naturalsize()) {
            naturalWidth = bezierPath.naturalsize().width();
            naturalHeight = bezierPath.naturalsize().height();
        }
        pathData = pathDataFromPath(bezierPath.path());
    } else if (pathSource.has_editable_bezier_path_source()) {
        const TSD::EditableBezierPathSourceArchive &editablePath = pathSource.editable_bezier_path_source();
        if (editablePath.has_naturalsize()) {
            naturalWidth = editablePath.naturalsize().width();
            naturalHeight = editablePath.naturalsize().height();
        }
        pathData = pathDataFromEditablePath(editablePath);
    } else {
        return false;
    }

    if (pathData.empty()) {
        return false;
    }

    const AffineTransform localTransform = transformForGeometry(
        drawableArchive.geometry(),
        naturalWidth,
        naturalHeight,
        pathSource.horizontalflip(),
        pathSource.verticalflip()
    );

    ExportedShape exportedShape;
    exportedShape.pathData = pathData;
    exportedShape.transform = multiply(parentTransform, localTransform);
    exportedShape.bounds = transformedRectBounds(exportedShape.transform, naturalWidth, naturalHeight);

    if (shapeArchive.has_style()) {
        parseStyleReference(messages, shapeArchive.style().identifier(), definitions, gradientCounter, &exportedShape.style);
    }

    shapes->push_back(std::move(exportedShape));
    return true;
}

bool collectDrawableChildren(const SerializedMessageMap &messages,
                             const google::protobuf::RepeatedPtrField<TSP::Reference> &children,
                             const AffineTransform &parentTransform,
                             std::unordered_set<google::protobuf::uint64> *visitedIdentifiers,
                             std::vector<std::string> *definitions,
                             size_t *gradientCounter,
                             std::vector<ExportedShape> *shapes) {
    bool exported = false;
    for (const auto &child : children) {
        exported = collectDrawable(
            messages,
            child.identifier(),
            parentTransform,
            visitedIdentifiers,
            definitions,
            gradientCounter,
            shapes
        ) || exported;
    }
    return exported;
}

bool collectDrawable(const SerializedMessageMap &messages,
                     google::protobuf::uint64 identifier,
                     const AffineTransform &parentTransform,
                     std::unordered_set<google::protobuf::uint64> *visitedIdentifiers,
                     std::vector<std::string> *definitions,
                     size_t *gradientCounter,
                     std::vector<ExportedShape> *shapes) {
    if (visitedIdentifiers == nullptr || shapes == nullptr) {
        return false;
    }

    if (visitedIdentifiers->find(identifier) != visitedIdentifiers->end()) {
        return false;
    }

    const auto iterator = messages.find(identifier);
    if (iterator == messages.end()) {
        return false;
    }

    visitedIdentifiers->insert(identifier);

    switch (iterator->second.type) {
        case 2011: {
            TSWP::ShapeInfoArchive shapeInfoArchive;
            if (!shapeInfoArchive.ParseFromString(iterator->second.payload) || !shapeInfoArchive.has_super()) {
                return false;
            }
            return collectShapeArchive(messages, shapeInfoArchive.super(), parentTransform, definitions, gradientCounter, shapes);
        }
        case 3004: {
            TSD::ShapeArchive shapeArchive;
            if (!shapeArchive.ParseFromString(iterator->second.payload)) {
                return false;
            }
            return collectShapeArchive(messages, shapeArchive, parentTransform, definitions, gradientCounter, shapes);
        }
        case 3003: {
            TSD::ContainerArchive containerArchive;
            if (!containerArchive.ParseFromString(iterator->second.payload)) {
                return false;
            }
            AffineTransform containerTransform = parentTransform;
            if (containerArchive.has_geometry()) {
                containerTransform = multiply(parentTransform, transformForGeometry(
                    containerArchive.geometry(),
                    containerArchive.geometry().has_size() ? containerArchive.geometry().size().width() : 1.0,
                    containerArchive.geometry().has_size() ? containerArchive.geometry().size().height() : 1.0,
                    false,
                    false
                ));
            }
            return collectDrawableChildren(messages, containerArchive.children(), containerTransform, visitedIdentifiers, definitions, gradientCounter, shapes);
        }
        case 3008: {
            TSD::GroupArchive groupArchive;
            if (!groupArchive.ParseFromString(iterator->second.payload)) {
                return false;
            }
            AffineTransform groupTransform = parentTransform;
            if (groupArchive.has_super() && groupArchive.super().has_geometry()) {
                const TSD::GeometryArchive &geometry = groupArchive.super().geometry();
                groupTransform = multiply(parentTransform, transformForGeometry(
                    geometry,
                    geometry.has_size() ? geometry.size().width() : 1.0,
                    geometry.has_size() ? geometry.size().height() : 1.0,
                    false,
                    false
                ));
            }
            return collectDrawableChildren(messages, groupArchive.children(), groupTransform, visitedIdentifiers, definitions, gradientCounter, shapes);
        }
        default:
            return false;
    }
}

std::string renderSVG(const std::vector<ExportedShape> &shapes, const std::vector<std::string> &definitions) {
    Bounds overallBounds;
    for (const ExportedShape &shape : shapes) {
        if (!shape.bounds.isValid()) {
            continue;
        }
        overallBounds.include(shape.bounds.minX, shape.bounds.minY);
        overallBounds.include(shape.bounds.maxX, shape.bounds.maxY);
    }

    if (!overallBounds.isValid()) {
        return {};
    }

    const double width = std::max(overallBounds.maxX - overallBounds.minX, 1.0);
    const double height = std::max(overallBounds.maxY - overallBounds.minY, 1.0);

    std::ostringstream stream;
    stream << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    stream << "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\""
           << formatFloat(width) << "\" height=\"" << formatFloat(height)
           << "\" viewBox=\"0 0 " << formatFloat(width) << ' ' << formatFloat(height) << "\">\n";

    if (!definitions.empty()) {
        stream << "  <defs>\n";
        for (const std::string &definition : definitions) {
            stream << "    " << definition << "\n";
        }
        stream << "  </defs>\n";
    }

    for (const ExportedShape &shape : shapes) {
        AffineTransform transform = shape.transform;
        transform.e -= overallBounds.minX;
        transform.f -= overallBounds.minY;

        stream << "  <path d=\"" << escapeXML(shape.pathData) << "\"";
        stream << " transform=\"matrix("
               << formatFloat(transform.a) << ' '
               << formatFloat(transform.b) << ' '
               << formatFloat(transform.c) << ' '
               << formatFloat(transform.d) << ' '
               << formatFloat(transform.e) << ' '
               << formatFloat(transform.f) << ")\"";
        stream << " fill=\"" << escapeXML(shape.style.fillNone ? "none" : shape.style.fillValue) << "\"";
        if (!shape.style.fillNone && shape.style.fillOpacity < 1.0 - kEpsilon) {
            stream << " fill-opacity=\"" << formatFloat(shape.style.fillOpacity) << "\"";
        }
        stream << " stroke=\"" << escapeXML(shape.style.hasStroke ? shape.style.strokeValue : "none") << "\"";
        if (shape.style.hasStroke) {
            stream << " stroke-width=\"" << formatFloat(shape.style.strokeWidth) << "\"";
            if (shape.style.strokeOpacity < 1.0 - kEpsilon) {
                stream << " stroke-opacity=\"" << formatFloat(shape.style.strokeOpacity) << "\"";
            }
            if (!shape.style.lineCap.empty()) {
                stream << " stroke-linecap=\"" << shape.style.lineCap << "\"";
            }
            if (!shape.style.lineJoin.empty()) {
                stream << " stroke-linejoin=\"" << shape.style.lineJoin << "\"";
            }
            if (shape.style.miterLimit > kEpsilon) {
                stream << " stroke-miterlimit=\"" << formatFloat(shape.style.miterLimit) << "\"";
            }
            if (!shape.style.dashArray.empty()) {
                stream << " stroke-dasharray=\"";
                for (size_t index = 0; index < shape.style.dashArray.size(); ++index) {
                    if (index > 0) {
                        stream << ' ';
                    }
                    stream << formatFloat(shape.style.dashArray[index]);
                }
                stream << "\"";
            }
        }
        if (shape.style.opacity < 1.0 - kEpsilon) {
            stream << " opacity=\"" << formatFloat(shape.style.opacity) << "\"";
        }
        stream << " />\n";
    }

    stream << "</svg>\n";
    return stream.str();
}

}  // namespace

std::string generateTSPNativeDataClipboardFromSVG(const std::string &svgContents) {
    std::vector<MessageWrapper *> objects = *convertSVGFileToKeynoteClipboard(svgContents);
    return convertListOfMessagesToProtoStream(objects);
}

std::string generateTSPNativeMetadataClipboard() {
    auto metadataMessageList = generateMetadataMessageList();
    return convertListOfMessagesToProtoStream(metadataMessageList);
}

std::string generateSVGFromTSPNativeDataClipboard(const std::string &clipboardData) {
    SerializedMessageMap messages;
    if (!parseClipboardMessageStream(clipboardData, &messages)) {
        return {};
    }

    TSP::PasteboardObject pasteboardObject;
    if (!parsePasteboardObject(messages, &pasteboardObject)) {
        return {};
    }

    std::unordered_set<google::protobuf::uint64> visitedIdentifiers;
    std::vector<std::string> definitions;
    std::vector<ExportedShape> shapes;
    size_t gradientCounter = 1;

    if (pasteboardObject.drawables_size() > 0) {
        for (const auto &reference : pasteboardObject.drawables()) {
            collectDrawable(messages, reference.identifier(), AffineTransform(), &visitedIdentifiers, &definitions, &gradientCounter, &shapes);
        }
    } else {
        for (const auto &reference : pasteboardObject.top_level_objects()) {
            collectDrawable(messages, reference.identifier(), AffineTransform(), &visitedIdentifiers, &definitions, &gradientCounter, &shapes);
        }
    }

    if (shapes.empty()) {
        return {};
    }

    return renderSVG(shapes, definitions);
}
