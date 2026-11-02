// Parses one set of raw props through three props structs as a component
// descriptor's cloneProps does: a RawPropsParser prepared for the struct once,
// then RawProps parsed with it and the struct constructed from them. It prints
// the reads RawPropsParser::at answered during the parse and the keys it
// compared their names with, which raw-props-parser-compared-keys.patch counts.
//
// - ViewOnlyProps is View's props and nothing more.
// - InOrderProps reads one key of its own, `tint`, after View's props.
// - OutOfOrderProps reads `width` after View's props, a key they read earlier.

#include <react/renderer/components/view/ViewProps.h>
#include <react/renderer/core/PropsParserContext.h>
#include <react/renderer/core/RawProps.h>
#include <react/renderer/core/RawPropsParser.h>
#include <react/renderer/core/propsConversions.h>
#include <react/utils/ContextContainer.h>

#include <folly/dynamic.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <type_traits>

namespace facebook::react {
extern std::atomic<std::uint64_t> reproducerReads;
extern std::atomic<std::uint64_t> reproducerComparedKeys;
} // namespace facebook::react

using namespace facebook::react;

namespace {

struct ViewOnlyProps : ViewProps {
  ViewOnlyProps() = default;
  ViewOnlyProps(
      const PropsParserContext& context,
      const ViewOnlyProps& sourceProps,
      const RawProps& rawProps)
      : ViewProps(context, sourceProps, rawProps) {}
};

struct InOrderProps : ViewProps {
  InOrderProps() = default;
  InOrderProps(
      const PropsParserContext& context,
      const InOrderProps& sourceProps,
      const RawProps& rawProps)
      : ViewProps(context, sourceProps, rawProps),
        tint(convertRawProp(context, rawProps, "tint", sourceProps.tint, 0)) {}

  int tint{0};
};

struct OutOfOrderProps : ViewProps {
  OutOfOrderProps() = default;
  OutOfOrderProps(
      const PropsParserContext& context,
      const OutOfOrderProps& sourceProps,
      const RawProps& rawProps)
      : ViewProps(context, sourceProps, rawProps),
        widthAgain(convertRawProp(
            context,
            rawProps,
            "width",
            sourceProps.widthAgain,
            0.0f)) {}

  float widthAgain{0.0f};
};

template <typename PropsT>
void parseAndCount(const char* name, const PropsParserContext& context) {
  RawPropsParser parser;
  parser.prepare<PropsT>();
  RawProps rawProps(
      folly::dynamic::object("width", 10)("height", 10)("tint", 1));
  rawProps.parse(parser);
  const auto readsBefore = reproducerReads.load();
  const auto comparedBefore = reproducerComparedKeys.load();
  const PropsT props(context, PropsT{}, rawProps);
  std::printf(
      "%-16s reads %llu, keys compared %llu\n",
      name,
      static_cast<unsigned long long>(reproducerReads.load() - readsBefore),
      static_cast<unsigned long long>(
          reproducerComparedKeys.load() - comparedBefore));
  if constexpr (std::is_same_v<PropsT, InOrderProps>) {
    std::printf("%-16s read tint %d\n", name, props.tint);
  }
  if constexpr (std::is_same_v<PropsT, OutOfOrderProps>) {
    std::printf("%-16s read width %.0f\n", name, props.widthAgain);
  }
}

} // namespace

int main() {
  ContextContainer contextContainer;
  const PropsParserContext context{-1, contextContainer};
  parseAndCount<ViewOnlyProps>("ViewOnlyProps", context);
  parseAndCount<InOrderProps>("InOrderProps", context);
  parseAndCount<OutOfOrderProps>("OutOfOrderProps", context);
  return 0;
}
