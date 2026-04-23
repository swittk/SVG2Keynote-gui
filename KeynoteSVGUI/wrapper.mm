#import "wrapper.h"

#import <Foundation/Foundation.h>

#include "Codec/keynote.hpp"
#include "Codec/proto_helper.h"
#include "KNArchives.pb.h"
#include "TSPArchiveMessages.pb.h"
#include "TSPMessages.pb.h"

static NSString *const kCompatibilityVersionKey = @"version";
static NSString *const kCompatibilityAppNameKey = @"appName";
static NSString *const kCompatibilityDataMetadataMapIdentifierKey = @"dataMetadataMapIdentifier";

static NSArray<NSNumber *> *NormalizedVersionComponentsFromString(NSString *versionString) {
    NSMutableArray<NSNumber *> *components = [NSMutableArray array];
    for (NSString *component in [versionString componentsSeparatedByString:@"."]) {
        if (component.length == 0) {
            continue;
        }
        NSInteger value = component.integerValue;
        [components addObject:@(MAX(value, 0))];
        if (components.count == 3) {
            break;
        }
    }

    while (components.count < 3) {
        [components addObject:@0];
    }

    return [components copy];
}

static google::protobuf::uint64 DefaultDataMetadataMapIdentifier(void) {
    return 2641470;
}

static NSArray<NSNumber *> *NormalizedCompatibilityVersionComponents(NSArray<NSNumber *> *components) {
    if (![components isKindOfClass:[NSArray class]] || components.count == 0) {
        return nil;
    }

    NSMutableArray<NSNumber *> *normalized = [NSMutableArray arrayWithCapacity:MAX((NSUInteger)3, components.count)];
    for (id component in components) {
        if (![component isKindOfClass:[NSNumber class]]) {
            continue;
        }
        [normalized addObject:@(MAX(((NSNumber *)component).integerValue, 0))];
    }

    while (normalized.count < 3) {
        [normalized addObject:@0];
    }

    return normalized.count > 0 ? [normalized copy] : nil;
}

static NSString *InstalledKeynoteVersionString(void) {
    NSBundle *bundle = [NSBundle bundleWithPath:@"/Applications/Keynote.app"];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version.length == 0) {
        return @"11.1";
    }
    return version;
}

static NSArray<NSNumber *> *InstalledKeynoteVersionComponents(void) {
    NSArray<NSNumber *> *components = NormalizedVersionComponentsFromString(InstalledKeynoteVersionString());
    NSInteger major = components.count > 0 ? components[0].integerValue : 0;
    NSInteger minor = components.count > 1 ? components[1].integerValue : 0;
    NSInteger patch = components.count > 2 ? components[2].integerValue : 0;

    // Keynote's clipboard metadata version is not always the same as CFBundleShortVersionString.
    // These values are taken from real Keynote clipboard payloads on current releases.
    if (major == 13 && minor == 0 && patch == 0) {
        patch = 2;
    } else if (major == 10 && minor == 1 && patch == 0) {
        patch = 8;
    } else if (major == 11 && minor == 2 && patch == 0) {
        patch = 9;
    } else if (major == 11 && minor == 1 && patch == 0) {
        patch = 2;
    }

    return @[ @(major), @(minor), @(patch) ];
}

static NSString *InstalledClipboardApplicationName(void) {
    return [@"com.apple.Keynote " stringByAppendingString:InstalledKeynoteVersionString()];
}

static NSDictionary<NSString *, id> *CompatibilityProfileFromMetadataData(NSData *metadataData) {
    if (metadataData.length == 0) {
        return nil;
    }

    google::protobuf::io::CodedInputStream stream(
        reinterpret_cast<const google::protobuf::uint8 *>(metadataData.bytes),
        (int)metadataData.length
    );

    google::protobuf::uint64 archiveInfoSize = 0;
    if (!stream.ReadVarint64(&archiveInfoSize)) {
        return nil;
    }

    TSP::ArchiveInfo archiveInfo;
    google::protobuf::io::CodedInputStream::Limit archiveLimit = stream.PushLimit((int)archiveInfoSize);
    const bool parsedArchiveInfo = archiveInfo.ParseFromCodedStream(&stream);
    stream.PopLimit(archiveLimit);
    if (!parsedArchiveInfo || archiveInfo.message_infos_size() == 0) {
        return nil;
    }

    const TSP::MessageInfo &messageInfo = archiveInfo.message_infos(0);
    if (messageInfo.type() != 11007 || messageInfo.length() <= 0) {
        return nil;
    }

    std::string payload;
    payload.resize(messageInfo.length());
    if (!stream.ReadRaw(payload.data(), messageInfo.length())) {
        return nil;
    }

    TSP::PasteboardMetadata pasteboardMetadata;
    if (!pasteboardMetadata.ParseFromString(payload) || !pasteboardMetadata.has_app_name()) {
        return nil;
    }

    NSMutableArray<NSNumber *> *version = [NSMutableArray arrayWithCapacity:MAX(3, pasteboardMetadata.version_size())];
    for (int index = 0; index < pasteboardMetadata.version_size(); ++index) {
        [version addObject:@(MAX((NSInteger)pasteboardMetadata.version(index), 0))];
    }
    NSArray<NSNumber *> *normalizedVersion = NormalizedCompatibilityVersionComponents(version);
    if (normalizedVersion == nil) {
        return nil;
    }

    NSString *appName = [[NSString alloc] initWithBytes:pasteboardMetadata.app_name().data()
                                                 length:pasteboardMetadata.app_name().length()
                                               encoding:NSUTF8StringEncoding];
    if (appName.length == 0 || ![appName hasPrefix:@"com.apple.Keynote "]) {
        return nil;
    }

    google::protobuf::uint64 dataMetadataMapIdentifier = DefaultDataMetadataMapIdentifier();
    if (pasteboardMetadata.has_data_metadata_map()) {
        dataMetadataMapIdentifier = pasteboardMetadata.data_metadata_map().identifier();
    }

    return @{
        kCompatibilityVersionKey: normalizedVersion,
        kCompatibilityAppNameKey: appName,
        kCompatibilityDataMetadataMapIdentifierKey: @(dataMetadataMapIdentifier),
    };
}

static TSP::UUID *CreateUUIDMessageFromString(NSString *documentUUIDString) {
    if (documentUUIDString.length == 0) {
        return nullptr;
    }

    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:documentUUIDString];
    if (uuid == nil) {
        return nullptr;
    }

    uuid_t bytes = {};
    [uuid getUUIDBytes:bytes];

    auto *uuidMessage = new TSP::UUID();
    google::protobuf::uint64 upper = 0;
    google::protobuf::uint64 lower = 0;
    for (NSInteger index = 0; index < 8; ++index) {
        upper = (upper << 8) | bytes[index];
        lower = (lower << 8) | bytes[index + 8];
    }
    uuidMessage->set_upper(upper);
    uuidMessage->set_lower(lower);
    return uuidMessage;
}

static NSData *GenerateClipboardMetadataData(NSString *documentUUIDString, NSDictionary<NSString *, id> *compatibilityProfile) {
    auto *pasteboardMetadata = new TSP::PasteboardMetadata();
    NSArray<NSNumber *> *metadataVersion = NormalizedCompatibilityVersionComponents(compatibilityProfile[kCompatibilityVersionKey]);
    if (metadataVersion == nil) {
        metadataVersion = InstalledKeynoteVersionComponents();
    }
    for (NSNumber *component in metadataVersion) {
        pasteboardMetadata->add_version(component.intValue);
    }

    NSString *applicationName = compatibilityProfile[kCompatibilityAppNameKey];
    if (![applicationName isKindOfClass:[NSString class]] || applicationName.length == 0) {
        applicationName = InstalledClipboardApplicationName();
    }
    pasteboardMetadata->set_allocated_app_name(new std::string(applicationName.UTF8String ?: ""));
    pasteboardMetadata->add_read_version(2);
    pasteboardMetadata->add_read_version(0);
    pasteboardMetadata->add_read_version(0);

    if (TSP::UUID *uuidMessage = CreateUUIDMessageFromString(documentUUIDString)) {
        pasteboardMetadata->set_allocated_source_document_uuid(uuidMessage);
    }

    google::protobuf::uint64 dataMetadataMapIdentifier = DefaultDataMetadataMapIdentifier();
    NSNumber *compatibilityIdentifier = compatibilityProfile[kCompatibilityDataMetadataMapIdentifierKey];
    if ([compatibilityIdentifier isKindOfClass:[NSNumber class]]) {
        dataMetadataMapIdentifier = compatibilityIdentifier.unsignedLongLongValue;
    }

    auto *dataMetadataMapReference = new TSP::Reference();
    dataMetadataMapReference->set_identifier(dataMetadataMapIdentifier);
    pasteboardMetadata->set_allocated_data_metadata_map(dataMetadataMapReference);

    auto *dataMetadataMap = new TSP::DataMetadataMap();
    MessageWrapper *metadataWrapper = createMessageWrapper(pasteboardMetadata, 11007, 52);
    TSP::MessageInfo *metadataMessageInfo = metadataWrapper->archiveInfo->mutable_message_infos(0);
    auto *fieldInfo = metadataMessageInfo->add_field_infos();
    auto *fieldPath = new TSP::FieldPath();
    fieldPath->add_path(6);
    fieldInfo->set_allocated_path(fieldPath);
    fieldInfo->set_type(TSP::FieldInfo_Type_ObjectReference);
    fieldInfo->set_unknown_field_rule(TSP::FieldInfo_UnknownFieldRule_IgnoreAndPreserve);
    metadataMessageInfo->add_object_references(dataMetadataMapIdentifier);

    std::vector<MessageWrapper *> metadataMessageList{
        metadataWrapper,
        createMessageWrapper(dataMetadataMap, 11015, dataMetadataMapIdentifier),
    };
    const std::string response = convertListOfMessagesToProtoStream(metadataMessageList);
    return [[NSData alloc] initWithBytes:response.data() length:response.length()];
}

static NSInteger CountDrawableReferencesInClipboardData(NSData *clipboardData) {
    if (clipboardData.length == 0) {
        return 0;
    }

    google::protobuf::io::CodedInputStream stream(
        reinterpret_cast<const google::protobuf::uint8 *>(clipboardData.bytes),
        (int)clipboardData.length
    );

    while (stream.BytesUntilLimit() > 0) {
        google::protobuf::uint64 archiveInfoSize = 0;
        if (!stream.ReadVarint64(&archiveInfoSize)) {
            break;
        }

        TSP::ArchiveInfo archiveInfo;
        google::protobuf::io::CodedInputStream::Limit archiveLimit = stream.PushLimit((int)archiveInfoSize);
        if (!archiveInfo.ParseFromCodedStream(&stream)) {
            stream.PopLimit(archiveLimit);
            break;
        }
        stream.PopLimit(archiveLimit);

        if (archiveInfo.message_infos_size() == 0) {
            break;
        }

        const TSP::MessageInfo &messageInfo = archiveInfo.message_infos(0);
        std::string payload;
        payload.resize(messageInfo.length());
        if (!stream.ReadRaw(payload.data(), messageInfo.length())) {
            break;
        }

        if (messageInfo.type() == 11000) {
            TSP::PasteboardObject pasteboardObject;
            if (pasteboardObject.ParseFromString(payload)) {
                return pasteboardObject.drawables_size();
            }
            break;
        }
    }

    return 0;
}

static NSData *GenerateClipboardDescriptionData(NSInteger drawableCount) {
    if (drawableCount < 1) {
        drawableCount = 1;
    }

    NSMutableArray<NSDictionary *> *drawableDescriptions = [NSMutableArray array];
    NSDictionary *emptyTextEntry = @{};
    for (NSInteger index = 0; index < drawableCount; ++index) {
        [drawableDescriptions addObject:@{
            @"class": @"TSWPShapeInfo",
            @"elementKind": @2,
            @"floatingAboveText": @YES,
            @"inlineWithText": @0,
            @"anchoredToText": @0,
            @"maxInlineNestingDepth": @1,
            @"text": @[ emptyTextEntry ],
        }];
    }

    NSDictionary *description = @{
        @"nativeObj": @{ @"KNPasteboardNativeStorage": @YES },
        @"drawables": drawableDescriptions,
    };

    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:description
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (data == nil) {
        return [NSData data];
    }
    return data;
}

@implementation CPP_Wrapper

- (NSData *)generateClipboardForTSPNativeData:(NSString *)svgContents {
    const std::string svg([svgContents UTF8String] ?: "");
    const std::string response = generateTSPNativeDataClipboardFromSVG(svg);
    return [[NSData alloc] initWithBytes:response.data() length:response.length()];
}

- (NSData *)generateClipboardMetadata {
    return [self generateClipboardMetadataWithDocumentUUIDString:NSUUID.UUID.UUIDString compatibilityProfile:nil];
}

- (NSData *)generateClipboardMetadataWithDocumentUUIDString:(NSString *)documentUUIDString {
    return [self generateClipboardMetadataWithDocumentUUIDString:documentUUIDString compatibilityProfile:nil];
}

- (NSData *)generateClipboardMetadataWithDocumentUUIDString:(NSString *)documentUUIDString compatibilityProfile:(NSDictionary<NSString *,id> *)compatibilityProfile {
    return GenerateClipboardMetadataData(documentUUIDString, compatibilityProfile);
}

- (NSData *)generateClipboardDescriptionForDrawableCount:(NSInteger)drawableCount {
    return GenerateClipboardDescriptionData(drawableCount);
}

- (NSInteger)drawableCountForClipboardData:(NSData *)clipboardData {
    return CountDrawableReferencesInClipboardData(clipboardData);
}

- (NSString *)svgStringFromClipboardData:(NSData *)clipboardData {
    if (clipboardData.length == 0) {
        return nil;
    }

    const std::string clipboard(
        static_cast<const char *>(clipboardData.bytes),
        static_cast<size_t>(clipboardData.length)
    );
    const std::string svg = generateSVGFromTSPNativeDataClipboard(clipboard);
    if (svg.empty()) {
        return nil;
    }

    return [[NSString alloc] initWithBytes:svg.data() length:svg.length() encoding:NSUTF8StringEncoding];
}

- (NSDictionary<NSString *,id> *)compatibilityProfileFromClipboardMetadataData:(NSData *)metadataData {
    return CompatibilityProfileFromMetadataData(metadataData);
}

@end
