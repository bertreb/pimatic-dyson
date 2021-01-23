module.exports = {
  title: "pimatic-dyson device config schemas"
  DysonDevice: {
    title: "DysonDevice config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties: {
      serial: 
        description: "The Dyson pure serial number"
        type: "string"
      type:
        description: "The Dyson pure type"
        type: "string"
      product:
        description: "The Dyson product description"
        type: "string"
      version:
        description: "The Dyson pure version"
        type: "string"
    }
  }
}
