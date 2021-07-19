//
//  File.swift
//
//
//  Created by alex slobodeniuk on 14.06.2021.
//

import SwiftUI


private struct PrivoVerificationState {
    var presentingVerification = false
    var privoStateId: String? = nil
}

private struct VerificationModal : View {
    @Binding fileprivate var state: PrivoVerificationState

    fileprivate var closeIcon: Image?
    fileprivate let onFinish: ((Array<VerificationEvent>) -> Void)?

    private func getConfig() -> WebviewConfig? {
        if let stateId = state.privoStateId,
           let verificationUrl = PrivoInternal.configuration.verificationUrl
                .withPath("/index.html")?
                .withQueryParam(name: "privo_state_id", value: stateId)?
                .withPath("/#/intro") {
            return WebviewConfig(
                url: verificationUrl,
                showCloseIcon: false,
                printCriteria: "/print",
                finishCriteria: "verification-loading",
                onFinish: { url in
                    if let items = URLComponents(string: url)?.queryItems,
                       let eventId = items.first(where: {$0.name == "privo_events_id"})?.value {
                        PrivoInternal.rest.getObjectFromTMPStorage(key: eventId) { (events: Array<VerificationEvent>?) in
                            state.presentingVerification = false
                            onFinish?(events ?? Array())
                        }
                    } else {
                        state.presentingVerification = false
                        onFinish?(Array())
                    }
                })
        }
        return nil
    }
    
    public var body: some View {
        if let config = getConfig() {
            ModalWebView(isPresented: $state.presentingVerification,  config:config)
        }
    }
}

public struct PrivoVerificationView<Label> : View where Label : View {

    public var profile: UserVerificationProfile?
    let label: Label
    var closeIcon: Image?
    let onFinish: ((Array<VerificationEvent>) -> Void)?
    
    private let verification = PrivoVerification()
    
    public init(@ViewBuilder label: () -> Label, onFinish: ((Array<VerificationEvent>) -> Void)? = nil, closeIcon: (() -> Image)? = nil, profile: UserVerificationProfile? = nil) {
        if let profile = profile {
            self.profile = profile
        }
        self.label = label()
        self.closeIcon = closeIcon?()
        self.onFinish = onFinish
    }
    func showView() {
        if let profile = profile {
            verification.setState(profile: profile)
        } else {
            verification.setState()
        }
    }
    public var body: some View {
        return Button {
            showView()
        } label: {
            label
        }.sheet(isPresented: verification.$state.presentingVerification) {
            VerificationModal(state: verification.$state, closeIcon: closeIcon, onFinish: onFinish)
        }
    }
}


public class PrivoVerification {
    public init() {}
    @State fileprivate var state = PrivoVerificationState()
    private let redirectUrl = PrivoInternal.configuration.verificationUrl.withPath("/#/verification-loading")!.absoluteString
    
    fileprivate func setState(profile: UserVerificationProfile = UserVerificationProfile()) -> Void {
        if let apiKey = PrivoInternal.settings.apiKey {
            let data = VerificationData(profile: profile, config: VerificationConfig(apiKey: apiKey, siteIdentifier: PrivoInternal.settings.serviceIdentifier), redirectUrl: redirectUrl)
            PrivoInternal.rest.addObjectToTMPStorage(value: data) { [weak self] id in
                self?.state.privoStateId = id
                self?.state.presentingVerification = true
            }
        }
    }
    public func showVerificationModal(profile: UserVerificationProfile = UserVerificationProfile(), completion: ((Array<VerificationEvent>) -> Void)?) {
        setState(profile: profile)
        UIApplication.shared.showView {
            VerificationModal(state: self.$state, onFinish: completion)
        }
    }
}
