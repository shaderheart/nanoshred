//
//  main.swift
//  scriptsToJson
//
//  Created by utku on 16/12/2022.
//

import Foundation

var outputPath = "./json.json"
var componentPath = "./cjson.json"
for i in 1 ..< Int(CommandLine.argc) {
    if let argValue = String?(CommandLine.arguments[i]) {
        print("arg:", argValue)
        if i == 1 {
            outputPath = argValue
        } else if i == 2 {
            componentPath = argValue
        }
    }
}

/// Encoes the given variable into a Data
/// - Parameters:
///   - payload: value to encode
///   - output: target Data instance
func encode<Value>(payload: Value, output: inout Data) where Value : Encodable {
    let encoder = JSONEncoder()
    output = try! encoder.encode(payload)
}


var scriptMap = [String: String]()
var componentMap = [String: String]()

for (key, scriptOpt) in AllScripts.allScripts {
    let script = scriptOpt
    var jsonEncoded = Data()
    encode(payload: script, output: &jsonEncoded)
    scriptMap[key] = String(decoding: jsonEncoded, as: UTF8.self)
}

for (component) in registerableComponents {
    var jsonEncoded = Data()
    encode(payload: component, output: &jsonEncoded)
    componentMap[String(describing: type(of:component))] = String(decoding: jsonEncoded, as: UTF8.self)
}

let json = try! JSONSerialization.data(withJSONObject: scriptMap, options: .prettyPrinted)
try! json.write(to: URL(fileURLWithPath: outputPath))

let cjson = try! JSONSerialization.data(withJSONObject: componentMap, options: .prettyPrinted)
try! cjson.write(to: URL(fileURLWithPath: componentPath))


