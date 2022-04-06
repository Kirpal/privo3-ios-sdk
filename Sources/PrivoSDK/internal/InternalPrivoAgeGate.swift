//
//  File.swift
//  
//
//  Created by alex slobodeniuk on 31.03.2022.
//

import Foundation
import SwiftUI

internal class InternalPrivoAgeGate {
    private let FP_ID_KEY = "privoFpId";
    private let AGE_EVENT_KEY = "AgeGateEvent"
    private let keychain = PrivoKeychain()
    private var serviceSettings: AgeServiceSettings? = nil
    
    internal init() {
        PrivoInternal.rest.getAgeServiceSettings(serviceIdentifier: PrivoInternal.settings.serviceIdentifier) { s in
            self.serviceSettings = s
        }
    }
    
    internal func storeAgeGateEvent(_ event: AgeGateEvent) {
        if let jsonData = try? JSONEncoder().encode(event) {
            let jsonString = String(decoding: jsonData, as: UTF8.self)
            keychain.set(key: AGE_EVENT_KEY, value: jsonString)
        }
    }
    
    internal func getAgeGateEvent(completionHandler: @escaping (AgeGateEvent?) -> Void) {
        if let jsonString = keychain.get(AGE_EVENT_KEY),
           let jsonData = jsonString.data(using: .utf8),
           let value = try? JSONDecoder().decode(AgeGateEvent.self, from: jsonData) {
             completionHandler(value)
         } else {
             completionHandler(nil)
         }
    }
    
    internal func runAgeGateByBirthDay(_ data: CheckAgeData, completionHandler: @escaping (AgeGateEvent?) -> Void) {
        getFpId() { fpId in
            if let birthDateYYYMMDD = data.birthDateYYYYMMDD,
               let fpId = fpId {
                // make a rest call
                let record = FpStatusRecord(
                    serviceIdentifier: PrivoInternal.settings.serviceIdentifier,
                    fpId: fpId,
                    birthDate: birthDateYYYMMDD,
                    extUserId: data.userIdentifier,
                    countryCode: data.countryCode
                )
                PrivoInternal.rest.processBirthDate(data: record) { [weak self] r in
                    if let response = r,
                       let status = self?.toStatus(response.action) {
                        let event = AgeGateEvent(
                            status: status,
                            userIdentifier: data.userIdentifier,
                            agId: response.ageGateIdentifier
                        )
                        completionHandler(event)
                    } else {
                        completionHandler(nil)
                    }
                }
            }
        }
    }
    
    private func prepareSettings(completionHandler: @escaping (AgeServiceSettings?,String?,AgeGateEvent?) -> Void) {
        var settings: AgeServiceSettings? = serviceSettings
        var fpId: String? = nil
        var lastEvent: AgeGateEvent? = nil
        
        let group = DispatchGroup()
        if (settings == nil) {
            group.enter()
            PrivoInternal.rest.getAgeServiceSettings(serviceIdentifier: PrivoInternal.settings.serviceIdentifier) { s in
                settings = s
                group.leave()
            }
        }
        group.enter()
        getFpId() { r in
            fpId = r
            group.leave()
        }
        group.enter()
        getAgeGateEvent() { event in
            lastEvent = event
            group.leave()
        }
        group.notify(queue: .main) {
            completionHandler(settings,fpId, lastEvent)
        }
        
        return ()
        
    }
    
    internal func runAgeGate(_ data: CheckAgeData, completionHandler: @escaping (AgeGateEvent?) -> Void) {
        
        prepareSettings() { (settings, fpId, lastEvent) in
            
            guard let settings = settings else {
                return
            }
            
            let agId = lastEvent?.userIdentifier == data.userIdentifier ? lastEvent?.agId : nil;
            // let status = lastEvent?.userIdentifier == data.userIdentifier ? lastEvent?.status : nil;
            
            let ageGateData = CheckAgeStoreData(
                serviceIdentifier: PrivoInternal.settings.serviceIdentifier,
                settings: settings,
                userIdentifier: data.userIdentifier,
                countryCode: data.countryCode,
                redirectUrl: "age-gate-done",
                agId: agId,
                fpId: fpId
            )
            UIApplication.shared.showView(false) {
                AgeGateView(ageGateData : ageGateData, onFinish: { events in
                    events.forEach { event in
                        completionHandler(event)
                    }
                    UIApplication.shared.dismissTopView()
                })
            }
        }
    }
    
    internal func getFpId(completionHandler: @escaping (String?) -> Void) {
        if let fpId = keychain.get(FP_ID_KEY) {
            completionHandler(fpId)
        } else {
            if let fingerprint = try? DeviceFingerprint() {
                PrivoInternal.rest.generateFingerprint(fingerprint: fingerprint) { [weak self] r in
                    if let id = r?.id,
                       let fpIdKey = self?.FP_ID_KEY {
                        self?.keychain.set(key: fpIdKey, value: id)
                    }
                    completionHandler(r?.id)
                }
            } else {
                completionHandler(nil)
            }
        }
    }
    /*
    internal func getVerificationResponse(_ events: [VerificationEvent], ageGateIdentifier: String) -> AgeGateStatus? {
        let aceptedVerification = events.first {$0.result?.verificationResponse.matchOutcome == VerificationOutcome.Pass};
        if (aceptedVerification != nil) {
            return AgeGateStatus(action: AgeGateAction.Allow, ageGateIdentifier: ageGateIdentifier)
        } else {
            return nil
        }
    }
     */
    
    internal func toStatus(_ action: AgeGateAction?) -> AgeGateStatus? {
        switch action {
            case .Allow:
                return AgeGateStatus.Allowed
            case .Block:
                return AgeGateStatus.Blocked
            case .Consent:
                return AgeGateStatus.Pending
            case .Verify:
                return AgeGateStatus.Pending
            default:
            return AgeGateStatus.Undefined
        }
    }
}

struct PrivoAgeGateState {
    var isPresented = false
    var inProgress = true
    var privoStateId: String? = nil
}


struct AgeGateView : View {
    @State var state: PrivoAgeGateState = PrivoAgeGateState()
    let ageGateData: CheckAgeStoreData?
    let onFinish: ((Array<AgeGateEvent>) -> Void)

    private func getConfig(_ stateId: String) -> WebviewConfig {
        let verificationUrl = PrivoInternal.configuration.ageGatePublicUrl
             .withPath("/index.html")?
             .withQueryParam(name: "privo_state_id", value: stateId)?
             .withPath("#/dob")
         return WebviewConfig(
             url: verificationUrl!,
             showCloseIcon: false,
             finishCriteria: "age-gate-done",
             onFinish: { url in
                 if let items = URLComponents(string: url)?.queryItems,
                    let eventId = items.first(where: {$0.name == "privo_age_gate_events_id"})?.value {
                     state.inProgress = true
                     PrivoInternal.rest.getObjectFromTMPStorage(key: eventId) { (events: Array<AgeGateEventInternal>?) in
                         let publicEvents = events?.map { $0.toEvent() }.compactMap { $0 }
                         finishView(publicEvents)
                     }
                 } else {
                     finishView(nil)
                 }
             })
    }
    func showView() {
        if let ageGateData = ageGateData {
            state.inProgress = true
            PrivoInternal.rest.addObjectToTMPStorage(value: ageGateData) { id in
                if (id != nil) {
                    self.state.isPresented = true
                    self.state.privoStateId = id
                }
                state.inProgress = false
            }
        }
    }
    private func finishView(_ events: Array<AgeGateEvent>?) {
        state.inProgress = false
        state.isPresented = false
        state.privoStateId = nil
        if let events = events {
            onFinish(events)
        }
    }
    
    public var body: some View {
        LoadingView(isShowing: $state.inProgress) {
            VStack {
                if (state.privoStateId != nil) {
                    ModalWebView(isPresented: $state.isPresented,  config: getConfig(state.privoStateId!))
                }
            }.onDisappear {
                finishView(nil)
            }
        }.onAppear {
            showView()
        }
    }
}
