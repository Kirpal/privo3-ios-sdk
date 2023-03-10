//
//  File.swift
//  
//
//  Created by alex slobodeniuk on 01.04.2022.
//

import Foundation

public struct AgeGateEvent: Decodable, Encodable, Hashable {
    public let status: AgeGateStatus
    public let userIdentifier: String?
    public let nickname: String?
    public let agId: String?
    public let ageRange: AgeRange?
    public let countryCode: String?
}
