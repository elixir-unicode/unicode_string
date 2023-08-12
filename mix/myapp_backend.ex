defmodule MyApp.Cldr do
  use Cldr,
    locales: ["en", "de", "tr", "az", "fr-CA", "lt", "fr", "sv", "ar"],
    default_locale: "en",
    providers: []
end