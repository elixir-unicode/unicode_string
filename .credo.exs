# Credo configuration for unicode_string.
#
# Policy decisions:
#
# * `Design.AliasUsage` is disabled. Fully-qualified calls to modules such
#   as `Unicode.String.Break` and `Unicode.String.Segment` read more clearly
#   at the call site than opportunistic aliases.
#
# * `Refactor.Nesting` and `Refactor.CyclomaticComplexity` stay at their
#   defaults; naturally-branchy functions (segmentation rule dispatch) carry
#   inline `credo:disable` annotations with a one-line justification rather
#   than a raised global limit.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
