data:extend({
  {
    type = "bool-setting",
    name = "factorial-enable-udp-bridge",
    setting_type = "runtime-global",
    default_value = false,
    order = "a"
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
    type = "bool-setting",
    name = "factorial-auto-poll-udp",
    setting_type = "runtime-global",
    default_value = true,
    order = "c"
  }
})
