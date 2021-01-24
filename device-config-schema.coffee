module.exports = {
  title: "pimatic-dyson device config schemas"
  DysonDevice: {
    title: "DysonDevice config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties: {
      serial: 
        description: "Dyson pure serial number"
        type: "string"
      type:
        description: "Dyson pure type"
        type: "string"
      product:
        description: "Dyson product description"
        type: "string"
      version:
        description: "Dyson pure version"
        type: "string"
    }
  }
}
