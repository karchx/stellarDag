import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :oraculo, Oraculo.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pyv/Cc/Xa9UuROgR5YmVBovkrKN59IPo84AOoS5o8P5Qql1IKx0vhdizWtdfL3Gu",
  server: false
