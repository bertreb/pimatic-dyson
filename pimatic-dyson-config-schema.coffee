# #pimatic-dyson configuration options
module.exports = {
  title: "pimatic-dyson configuration options"
  type: "object"
  properties:
    email:
      descpription: "The email address for your dyson account"
      type: "string"
    password:
      descpription: "The password for your dyson account"
      type: "string"
    countrycode:
      descpription: "Your country code"
      type: "string"
      default: "US"
    polltime:
      descpription: "Time for update in values (default 1 minute)"
      type: "number"
      default: 60000
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
}
