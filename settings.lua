data:extend({
  {
    type = "string-setting",
    name = "factorial-default-advisor",
    setting_type = "runtime",
    default_value = "internal",
    allowed_values = {"internal", "external", "local-llm"},
    order = "a"
  },
  {
    type = "bool-setting",
    name = "factorial-enable-udp-bridge",
    setting_type = "runtime-global",
    default_value = false,
    order = "b"
  },
  {
    type = "int-setting",
    name = "factorial-udp-port",
    setting_type = "runtime-global",
    default_value = 34198,
    minimum_value = 1024,
    maximum_value = 65535,
    order = "b"
  },
  {
    type = "int-setting",
    name = "factorial-udp-receive-port",
    setting_type = "runtime-global",
    default_value = 34199,
    minimum_value = 1024,
    maximum_value = 65535,
    order = "c"
  },
  {
    type = "string-setting",
    name = "factorial-lmstudio-url",
    setting_type = "runtime-global",
    default_value = "http://192.168.1.53:1234",
    allow_blank = false,
    order = "d"
  },
  {
    type = "bool-setting",
    name = "factorial-auto-poll-udp",
    setting_type = "runtime-global",
    default_value = true,
    order = "e"
  },
  {
    type = "bool-setting",
    name = "factorial-dev-mode",
    setting_type = "runtime-global",
    default_value = false,
    order = "f"
  }
})
