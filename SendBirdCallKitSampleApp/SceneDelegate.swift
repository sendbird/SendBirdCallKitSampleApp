//
//  SceneDelegate.swift
//  SendBirdCallKitSampleApp
//
//  Created by Ritesh Gupta on 21/05/23.
//

import UIKit
import CallKit
import AVFoundation
import SendBirdCalls

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	var window: UIWindow?

	var callManager: CXCallManager = .shared

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		// Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
		// If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
		// This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
		guard let _ = (scene as? UIWindowScene) else { return }
		// 1D514BE0-5A9A-4FF2-ADB1-E2936B8E689D
		SendBirdCall.configure(appId: "add_your_app_id")
	}

	func sceneDidDisconnect(_ scene: UIScene) {
		// Called as the scene is being released by the system.
		// This occurs shortly after the scene enters the background, or when its session is discarded.
		// Release any resources associated with this scene that can be re-created the next time the scene connects.
		// The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
	}

	func sceneDidBecomeActive(_ scene: UIScene) {
		// Called when the scene has moved from an inactive state to an active state.
		// Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
	}

	func sceneWillResignActive(_ scene: UIScene) {
		// Called when the scene will move from an active state to an inactive state.
		// This may occur due to temporary interruptions (ex. an incoming phone call).
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		// Called as the scene transitions from the background to the foreground.
		// Use this method to undo the changes made on entering the background.
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		// Called as the scene transitions from the foreground to the background.
		// Use this method to save data, release shared resources, and store enough scene-specific state information
		// to restore the scene back to its current state.
	}
}

class CXCallManager: NSObject {
	static let shared = CXCallManager()
	
	var currentCalls: [CXCall] { self.controller.callObserver.calls }
	
	private let provider: CXProvider
	private let controller = CXCallController()
	
	override init() {
		self.provider = CXProvider.default
		
		super.init()
		
		self.provider.setDelegate(self, queue: .main)
	}
	
	func shouldProcessCall(for callId: UUID) -> Bool {
		return !self.currentCalls.contains(where: { $0.uuid == callId })
	}
}

extension CXCallManager { // Process with CXProvider
	func reportIncomingCall(with callID: UUID, update: CXCallUpdate, completionHandler: ((Error?) -> Void)? = nil) {
		self.provider.reportNewIncomingCall(with: callID, update: update) { (error) in
			completionHandler?(error)
		}
	}
	
	func endCall(for callId: UUID, endedAt: Date, reason: DirectCallEndResult) {
		guard let endReason = reason.asCXCallEndedReason else { return }
		self.provider.reportCall(with: callId, endedAt: endedAt, reason: endReason)
	}
	
	func connectedCall(_ call: DirectCall) {
		self.provider.reportOutgoingCall(with: call.callUUID!, connectedAt: Date(timeIntervalSince1970: Double(call.startedAt)/1000))
	}
}

extension CXCallManager { // Process with CXTransaction
	func requestTransaction(_ transaction: CXTransaction, action: String = "") {
		self.controller.request(transaction) { error in
			guard error == nil else {
				print("Error Requesting Transaction: \(String(describing: error))")
				return
			}
			// Requested transaction successfully
		}
	}
	
	func startCXCall(_ call: DirectCall, completionHandler: @escaping ((Bool) -> Void)) {
		guard let calleeId = call.callee?.userId else {
			DispatchQueue.main.async {
				completionHandler(false)
			}
			return
		}
		let handle = CXHandle(type: .generic, value: calleeId)
		let startCallAction = CXStartCallAction(call: call.callUUID!, handle: handle)
		startCallAction.isVideo = call.isVideoCall
		
		let transaction = CXTransaction(action: startCallAction)
		
		self.requestTransaction(transaction)
		
		DispatchQueue.main.async {
			completionHandler(true)
		}
	}
	
	func endCXCall(_ call: DirectCall) {
		let endCallAction = CXEndCallAction(call: call.callUUID!)
		let transaction = CXTransaction(action: endCallAction)
		self.requestTransaction(transaction)
	}
}

extension CXCallManager: CXProviderDelegate {
	func providerDidReset(_ provider: CXProvider) { }
	
	func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
		// MARK: SendBirdCalls - SendBirdCall.getCall()
		guard let call = SendBirdCall.getCall(forUUID: action.callUUID) else {
			action.fail()
			return
		}
		
		if call.myRole == .caller {
			provider.reportOutgoingCall(with: call.callUUID!, startedConnectingAt: Date(timeIntervalSince1970: Double(call.startedAt)/1000))
		}
		
		action.fulfill()
	}
	
	func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
		guard let call = SendBirdCall.getCall(forUUID: action.callUUID) else {
			action.fail()
			return
		}
		
		// MARK: SendBirdCalls - DirectCall.accept()
		let callOptions = CallOptions(isAudioEnabled: true, isVideoEnabled: call.isVideoCall, useFrontCamera: true)
		let acceptParams = AcceptParams(callOptions: callOptions)
		call.accept(with: acceptParams)
		action.fulfill()
	}
	
	func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
		guard let call = SendBirdCall.getCall(forUUID: action.callUUID) else {
			action.fail()
			return
		}
		
		// MARK: SendBirdCalls - DirectCall.muteMicrophone / .unmuteMicrophone()
		action.isMuted ? call.muteMicrophone() : call.unmuteMicrophone()
		
		action.fulfill()
	}
	
	func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
		// Retrieve the SpeakerboxCall instance corresponding to the action's call UUID
		guard let call = SendBirdCall.getCall(forUUID: action.callUUID) else {
			action.fail()
			return
		}
		call.end {
			action.fulfill()
		}
	}
	
	func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) { }
	
	// In order to properly manage the usage of AVAudioSession within CallKit, please implement this function as shown below.
	func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
		SendBirdCall.audioSessionDidActivate(audioSession)
	}
	
	// In order to properly manage the usage of AVAudioSession within CallKit, please implement this function as shown below.
	func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
		SendBirdCall.audioSessionDidDeactivate(audioSession)
	}
}

extension DirectCallEndResult {
	var asCXCallEndedReason: CXCallEndedReason? {
		switch self {
		case .connectionLost, .timedOut, .acceptFailed, .dialFailed, .unknown:
			return .failed
		case .completed, .canceled:
			return .remoteEnded
		case .declined:
			return .declinedElsewhere
		case .noAnswer:
			return .unanswered
		case .otherDeviceAccepted:
			return .answeredElsewhere
		case .none: return nil
		@unknown default: return nil
		}
	}
}

extension CXProviderConfiguration {
	// The app's provider configuration, representing its CallKit capabilities
	static var `default`: CXProviderConfiguration {
		let providerConfiguration = CXProviderConfiguration()
		providerConfiguration.iconTemplateImageData = UIImage(systemName: "globe").flatMap { $0.pngData() }
		providerConfiguration.supportsVideo = true
		providerConfiguration.maximumCallsPerCallGroup = 1
		providerConfiguration.maximumCallGroups = 1
		providerConfiguration.supportedHandleTypes = [.generic]
		
		// Set up ringing sound
		 providerConfiguration.ringtoneSound = "Ringing.mp3"
		
		return providerConfiguration
	}
}

extension CXProvider {
	static var `default`: CXProvider {
		CXProvider(configuration: .default)
	}
}
