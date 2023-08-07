//
//  ViewController.swift
//  SendBirdCallKitSampleApp
//
//  Created by Ritesh Gupta on 21/05/23.
//

import UIKit
import SendBirdCalls
import PushKit
import CallKit

class ViewController: UIViewController, SendBirdCallDelegate, DirectCallDelegate, PKPushRegistryDelegate {
	var voipRegistry: PKPushRegistry!

	@IBOutlet var callUserButton: UIButton!
	@IBOutlet var disconnectCallButton: UIButton!

	var currentCall: DirectCall?

	override func viewDidLoad() {
		super.viewDidLoad()
		print(#function)
		
		disconnectCallButton.isEnabled = false
		
		SendBirdCall.addDelegate(self, identifier: UUID().uuidString)

		let params = AuthenticateParams(userId: "user_4", accessToken: "user_4_access_token")
		SendBirdCall.authenticate(with: params) { (user, error) in
			guard let user = user, error == nil else {
				print(error?.localizedDescription as Any)
				return
			}
			print(user.userId)
			self.voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
			self.voipRegistry.delegate = self
			self.voipRegistry.desiredPushTypes = [.voIP]
		}
	}
	
	@IBAction func didTapCall(_ sender: UIButton) {
		guard callUserButton.tintColor == .systemBlue else { return }
		updateCallButton(with: "Calling \"user_3\"...", tint: .systemGray)
		
		let params = DialParams(calleeId: "user_3", callOptions: CallOptions())
		let directCall = SendBirdCall.dial(with: params) { directCall, error in
			guard let directCall = directCall else { return }
			CXCallManager.shared.startCXCall(directCall) { success in
				print(success)
			}
		}
		directCall?.delegate = self
	}
	
	@IBAction func didTapToDisconnectCall(_ sender: UIButton) {
		guard let call = currentCall else { return }
		guard let call = SendBirdCall.getCall(forCallId: call.callId) else { return }
		call.end()
		CXCallManager.shared.endCXCall(call)
	}
	
	private func updateCallButton(with text: String, tint: UIColor) {
		callUserButton.setTitle(text, for: .normal)
		callUserButton.tintColor = tint
	}
	
	func didStartRinging(_ call: DirectCall) {
		print(#function)
		call.delegate = self // To receive call event through `DirectCallDelegate`
		// Use CXProvider to report the incoming call to the system
		// Construct a CXCallUpdate describing the incoming call, including the caller.
		let name = call.caller?.userId ?? "Unknown"
		let update = CXCallUpdate()
		update.remoteHandle = CXHandle(type: .generic, value: name)
		update.hasVideo = call.isVideoCall
		update.localizedCallerName = call.caller?.userId ?? "Unknown"

		CXCallManager.shared.reportIncomingCall(with: call.callUUID ?? .init(), update: update)
		updateCallButton(with: "Getting a call from \"user_3\"", tint: .systemGray)
	}
	
	func didReceiveInvitation(_ invitation: RoomInvitation) {
		print(#function)
	}
	
	func didConnect(_ call: SendBirdCalls.DirectCall) {
		print(#function)
		disconnectCallButton.isEnabled = true
		currentCall = call
		call.accept(with: .init(callOptions: .init()))
		updateCallButton(with: "Connected with \"user_3\"", tint: .systemGreen)
	}
	
	func didEnd(_ call: SendBirdCalls.DirectCall) {
		disconnectCallButton.isEnabled = false
		currentCall = nil
		print(#function)
		let callId: UUID = call.callUUID ?? UUID()
		CXCallManager.shared.endCall(for: callId, endedAt: Date(), reason: call.endResult)
		updateCallButton(with: "Disconnected with \"user_3\"", tint: .systemRed)
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
			self.updateCallButton(with: "Call \"user_3\"", tint: .systemBlue)
		}
	}
		
	// MARK: - SendBirdCalls - Receive incoming push event
	func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
		print(#function)
		SendBirdCall.pushRegistry(registry, didReceiveIncomingPushWith: payload, for: type, completionHandler: nil)
	}
	
	// MARK: - SendBirdCalls - Receive incoming push event
	func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
		print(#function)
		SendBirdCall.pushRegistry(registry, didReceiveIncomingPushWith: payload, for: type) { uuid in
			completion()
		}
	}
	
	// MARK: - SendBirdCalls - Receive push token
	func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
		print(#function)
		SendBirdCall.registerVoIPPush(token: pushCredentials.token, unique: false) { (error) in
		}
	}
}

