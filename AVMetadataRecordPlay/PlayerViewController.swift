/*
	Copyright (C) 2017 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Player view controller
*/

import UIKit
import AVFoundation
import CoreMedia
import ImageIO
import Alamofire

class PlayerViewController: UIViewController, AVPlayerItemMetadataOutputPushDelegate {
	
	
	// MARK: View Controller Life Cycle
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		playButton.isEnabled = false
		pauseButton.isEnabled = false
		
		playerView.layer.backgroundColor = UIColor.black.cgColor
		
		let metadataQueue = DispatchQueue(label: "com.example.metadataqueue", attributes: [])
		itemMetadataOutput.setDelegate(self, queue: metadataQueue)
		
		createAVAsset()

	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		
		// Pause the player and start from the beginning if the view reappears.
		player?.pause()
		if playerAsset != nil {
			playButton.isEnabled = true
			pauseButton.isEnabled = false
			seekToZeroBeforePlay = false
			player?.seek(to: kCMTimeZero)
		}
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		
		/*
			If device is rotated manually while playing back, and before the next orientation track is received,
			then playerLayer's frame should be changed to match with the playerView bounds.
		*/
		coordinator.animate(alongsideTransition: { _ in
				self.playerLayer?.frame = self.playerView.layer.bounds
			},
			completion: nil)
	}
	
	// MARK: Segue
	
	@IBAction func unwindBackToPlayer(segue: UIStoryboardSegue) {
		/*
		// Pull any data from the view controller which initiated the unwind segue.
		let assetGridViewController = segue.source as! AssetGridViewController
		if let selectedAsset = assetGridViewController.selectedAsset {
			if selectedAsset != playerAsset {
				setUpPlayback(for: selectedAsset)
				playerAsset = selectedAsset
			}
		}
*/
	}
	
	// MARK
	@IBOutlet private weak var progressIndicator : UIProgressView!
	@IBOutlet private weak var envoiEnCours : UILabel!
	//var progressIndicator = UIProgressView()
	
	// MARK: Player
	
	public var outputFileURL: URL?
	
	public var outputFileMp4URL: URL?
	
	private var player: AVPlayer?
	
	private var seekToZeroBeforePlay = false
	
	private var playerAsset: AVAsset?
	
	@IBOutlet private weak var playerView: UIView!
	
	private var playerLayer: AVPlayerLayer?
	
	private var defaultVideoTransform = CGAffineTransform.identity
	
	// création de l'Asset Vidéo à partir du chemin du fichier
	private func createAVAsset() {
		if (outputFileURL != nil) {
		let	playerAssetTemp = AVAsset.init(url : outputFileURL!)
		playerAsset = playerAssetTemp
		setUpPlayback(for: playerAssetTemp)
		}
	}
	
	
	private func setUpPlayback(for asset: AVAsset) {
		DispatchQueue.main.async {
			if let currentItem = self.player?.currentItem {
				currentItem.remove(self.itemMetadataOutput)
			}
			self.setUpPlayer(for: asset)
			self.playButton.isEnabled = true
			self.pauseButton.isEnabled = false
			self.removeAllSublayers(from: self.facesLayer)
		}
	}
	
	private func setUpPlayer(for asset: AVAsset) {
		let mutableComposition = AVMutableComposition()
		
		// Create a mutableComposition for all the tracks present in the asset.
		guard let sourceVideoTrack = asset.tracks(withMediaType: AVMediaTypeVideo).first else {
			print("Could not get video track from asset")
			return
		}
		defaultVideoTransform = sourceVideoTrack.preferredTransform
		
		let sourceAudioTrack = asset.tracks(withMediaType: AVMediaTypeAudio).first
		let mutableCompositionVideoTrack = mutableComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
		let mutableCompositionAudioTrack = mutableComposition.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
		
		do {
			try mutableCompositionVideoTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration), of: sourceVideoTrack, at: kCMTimeZero)
			if let sourceAudioTrack = sourceAudioTrack {
				try mutableCompositionAudioTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration), of: sourceAudioTrack, at: kCMTimeZero)
			}
		}
		catch {
			print("Could not insert time range into video/audio mutable composition: \(error)")
		}
		
		for metadataTrack in asset.tracks(withMediaType: AVMediaTypeMetadata) {
			if track(metadataTrack, hasMetadataIdentifier:AVMetadataIdentifierQuickTimeMetadataDetectedFace) ||
				track(metadataTrack, hasMetadataIdentifier:AVMetadataIdentifierQuickTimeMetadataVideoOrientation) ||
				track(metadataTrack, hasMetadataIdentifier:AVMetadataIdentifierQuickTimeMetadataLocationISO6709) {
				
				let mutableCompositionMetadataTrack = mutableComposition.addMutableTrack(withMediaType: AVMediaTypeMetadata, preferredTrackID: kCMPersistentTrackID_Invalid)
				
				do {
					try mutableCompositionMetadataTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration), of: metadataTrack, at: kCMTimeZero)
				}
				catch let error as NSError {
					print("Could not insert time range into metadata mutable composition: \(error)")
				}
			}
		}
		
		// Get an instance of AVPlayerItem for the generated mutableComposition.
		// let playerItem = AVPlayerItem(asset: asset) // This doesn't support video orientation hence we use a mutable composition.
		let playerItem = AVPlayerItem(asset: mutableComposition)
		playerItem.add(itemMetadataOutput)

		if let player = player {
			player.replaceCurrentItem(with: playerItem)
		}
		else {
			// Create AVPlayer with the generated instance of playerItem. Also add the facesLayer as subLayer to this playLayer.
			player = AVPlayer(playerItem: playerItem)
			player?.actionAtItemEnd = .none
			
			let playerLayer = AVPlayerLayer(player: player)
			playerLayer.backgroundColor = UIColor.black.cgColor
			playerLayer.addSublayer(facesLayer)
			playerView.layer.addSublayer(playerLayer)
			facesLayer.frame = playerLayer.videoRect;
			
			self.playerLayer = playerLayer
		}
		
		// Update the player layer to match the video's default transform. Disable animation so the transform applies immediately.
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		playerLayer?.transform = CATransform3DMakeAffineTransform(defaultVideoTransform)
		playerLayer?.frame = playerView.layer.bounds
		CATransaction.commit()
		
		// When the player item has played to its end time we'll toggle the movie controller Pause button to be the Play button.
		NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
		
		seekToZeroBeforePlay = false
	}
	
	/// Called when the player item has played to its end time.
	func playerItemDidReachEnd(_ notification: Notification) {
		// After the movie has played to its end time, seek back to time zero to play it again.
		seekToZeroBeforePlay = true
		playButton.isEnabled = true
		pauseButton.isEnabled = false
		removeAllSublayers(from: facesLayer)
		askForUpload()
	}
	
	private func askForUpload() {
		
		let uploadAlert = UIAlertController(title: "information", message: "Voulez-vous partager cette vidéo ? Do you want to share this video ?", preferredStyle: UIAlertControllerStyle.alert)
		
		uploadAlert.addAction(UIAlertAction(title: "Oui", style: .default, handler: { (action: UIAlertAction!) in
			print("oui")
			// gestion du cas où la vidéo a déjà été encodé mais n'a pu être envoyée à cause d'une ereur réseau
			if (self.outputFileMp4URL == nil) { 
					self.encodeVideo(videoURL: self.outputFileURL!)
			}
			else {
				self.transfertFileToServer()
			}
	
		}))
		
		uploadAlert.addAction(UIAlertAction(title: "Non", style: .default, handler: { (action: UIAlertAction!) in
			print("non")
			self.cleanUp();
			//self.presentHomeView()
			self.presentCameraView()
		}))
		
		uploadAlert.addAction(UIAlertAction(title: "Revoir", style: .default, handler: { (action: UIAlertAction!) in
			print("revoir avant")
			if self.seekToZeroBeforePlay {
				self.seekToZeroBeforePlay = false
				self.player?.seek(to: kCMTimeZero)
				
				// Update the player layer to match the video's default transform.
				self.playerLayer?.transform = CATransform3DMakeAffineTransform(self.defaultVideoTransform)
				self.playerLayer?.frame = self.playerView.layer.bounds
			}
			self.player?.play()
			self.playButton.isEnabled = false
			self.pauseButton.isEnabled = true
		}))
		
		self.present(uploadAlert, animated: true, completion: nil)
	}
	
	private func cleanUp() {
		let path = self.outputFileURL!.path
		if FileManager.default.fileExists(atPath: path) {
			do {
				try FileManager.default.removeItem(atPath: path)
			}
			catch {
				print("Could not remove file at url: \(self.outputFileURL!)")
			}
		}
		
		if (self.outputFileMp4URL != nil) {
			let path2 = self.outputFileMp4URL!.path
			if FileManager.default.fileExists(atPath: path2) {
				do {
					try FileManager.default.removeItem(atPath: path2)
					self.outputFileMp4URL = nil
				}
				catch {
					print("Could not remove file at url: \(self.outputFileMp4URL!)")
				}
			}
		}
	}
	
	
	// envoi du fichier su serveur
	private func transfertFileToServer() {
		// ok marche
		print("transfert File to serve");
		
		//let fileURL = URL(fileURLWithPath: self.outputFileURL!.path)
		let fileURL = URL(fileURLWithPath: self.outputFileMp4URL!.path)
		Alamofire.upload(multipartFormData: {multipartFormData in
			multipartFormData.append(fileURL, withName: "video")
		}, to:"http://bcom.insensa.fr/uploadVideo",
		   encodingCompletion: { encodingResult in
			switch encodingResult {
			case .success(let upload, _, _):
					UIApplication.shared.beginIgnoringInteractionEvents()
					self.progressIndicator.alpha = 1
					self.envoiEnCours.alpha = 1
				upload.uploadProgress { progress in
					print(progress.fractionCompleted)
					self.progressIndicator.setProgress(Float(progress.fractionCompleted), animated: true)
				}
				upload.responseJSON { response in
					debugPrint(response.response ?? "no response")
					if (response.response == nil || response.response?.statusCode != 200) {
						let uploadAlert = UIAlertController(title: "Information", message: "Erreur, la vidéo n'a pas été mise en ligne. Vérifiez votre connexion !", preferredStyle: UIAlertControllerStyle.alert)
					uploadAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action: UIAlertAction!) in
					}))
					self.present(uploadAlert, animated: true, completion: nil)
					}
					
					else {
						let uploadAlert = UIAlertController(title: "information", message: "La vidéo a été mise en ligne !", preferredStyle: UIAlertControllerStyle.alert)
						uploadAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action: UIAlertAction!) in
							self.cleanUp()
							self.presentHomeView()
						}))
						self.present(uploadAlert, animated: true, completion: nil)
					}
					
					self.progressIndicator.alpha = 0
					self.envoiEnCours.alpha = 0
					UIApplication.shared.endIgnoringInteractionEvents()
				}
			case .failure(let encodingError):
				print(encodingError)
				
				let uploadAlert = UIAlertController(title: "information", message: "Désolé, une erreur est survenue at la vidéo n'a pas été mise en ligne !", preferredStyle: UIAlertControllerStyle.alert)
				uploadAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action: UIAlertAction!) in
				}))
				self.present(uploadAlert, animated: true, completion: nil)
			}
		})
	}
	
	
	func encodeVideo(videoURL: URL){
		print("encode video")
		let avAsset = AVURLAsset(url: videoURL)
		let startDate = Date()
		let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetPassthrough)
		let outputFileName = URL(fileURLWithPath: videoURL.absoluteString).deletingPathExtension().lastPathComponent
		print("outputFileName : \(outputFileName)")
		let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mp4")!)
		self.outputFileMp4URL = NSURL.fileURL(withPath: outputFilePath)
		
		exportSession?.outputURL = self.outputFileMp4URL
		exportSession?.outputFileType = AVFileTypeMPEG4
		exportSession?.shouldOptimizeForNetworkUse = true
		
		let start = CMTimeMakeWithSeconds(0.0, 0) // début de la vidéo à exporter
		let range = CMTimeRange(start: start, duration: avAsset.duration) // fin de la vidéo à exporter
		exportSession?.timeRange = range // on exporte toute la vidéo
		
		exportSession!.exportAsynchronously{() -> Void in
			switch exportSession!.status{
			case .failed:
				print("erreur d'exportation : \(exportSession!.error!)")
			case .cancelled:
				print("Export cancelled")
			case .completed:
				let endDate = Date()
				let time = endDate.timeIntervalSince(startDate)
				print(time)
				print("Successfull")
				print(exportSession?.outputURL ?? "")
				self.transfertFileToServer()
			default:
				break
			}
		}
	}
	
	/*
	func deleteFile(_ filePath:URL) {
		guard FileManager.default.fileExists(atPath: filePath.path) else{
			return
		}
		do {
			try FileManager.default.removeItem(atPath: filePath.path)
		}catch{
			fatalError("Unable to delete file: \(error) : \(#function).")
		}
	}
*/
	
	
	
	
	
	private func presentCameraView() {
		self.navigationController?.popViewController(animated: true)
	}
	
	private func presentHomeView() {
		self.navigationController?.popToRootViewController(animated: true)
	}
	
	
	@IBOutlet private weak var playButton: UIBarButtonItem!
	
	@IBAction private func playButtonTapped(_ sender: AnyObject) {
		if seekToZeroBeforePlay {
			seekToZeroBeforePlay = false
			player?.seek(to: kCMTimeZero)
			
			// Update the player layer to match the video's default transform.
			playerLayer?.transform = CATransform3DMakeAffineTransform(defaultVideoTransform)
			playerLayer?.frame = playerView.layer.bounds
		}
		
		player?.play()
		playButton.isEnabled = false
		pauseButton.isEnabled = true
	}
	
	@IBOutlet private weak var pauseButton: UIBarButtonItem!
	
	@IBAction private func pauseButtonTapped(_ sender: AnyObject) {
		player?.pause()
		playButton.isEnabled = true
		pauseButton.isEnabled = false
	}
	
	// MARK: Timed Metadata
	
	private let itemMetadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
	
	private var honorTimedMetadataTracksDuringPlayback = false
	
	@IBOutlet private weak var honorTimedMetadataTracksSwitch: UISwitch!
	
	@IBAction private func toggleHonorTimedMetadataTracksDuringPlayback(_ sender: AnyObject) {
		if honorTimedMetadataTracksSwitch.isOn {
			honorTimedMetadataTracksDuringPlayback = true
		}
		else {
			honorTimedMetadataTracksDuringPlayback = false
			removeAllSublayers(from: facesLayer)
			locationOverlayLabel.text = ""
		}
	}
	
	func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack) {
		for metadataGroup in groups {
			
			DispatchQueue.main.async {
				
				// Sometimes the face/location track wouldn't contain any items because of scene change, we should remove previously drawn faceRects/locationOverlay in that case.
				if metadataGroup.items.count == 0 {
					if self.track(track.assetTrack, hasMetadataIdentifier: AVMetadataIdentifierQuickTimeMetadataDetectedFace) {
						self.removeAllSublayers(from: self.facesLayer)
					}
					else if self.track(track.assetTrack, hasMetadataIdentifier: AVMetadataIdentifierQuickTimeMetadataVideoOrientation) {
						self.locationOverlayLabel.text = ""
					}
				}
				else {
					if self.honorTimedMetadataTracksDuringPlayback {
						
						var faces = [AVMetadataObject]()
						
						for metdataItem in metadataGroup.items {
							guard let itemIdentifier = metdataItem.identifier, let itemDataType = metdataItem.dataType else {
								continue
							}
							
							switch itemIdentifier {
								case AVMetadataIdentifierQuickTimeMetadataDetectedFace:
									if let itemValue = metdataItem.value as? AVMetadataObject {
										faces.append(itemValue)
									}
									
								case AVMetadataIdentifierQuickTimeMetadataVideoOrientation:
									if itemDataType == String(kCMMetadataBaseDataType_SInt16) {
										if let videoOrientationValue = metdataItem.value as? NSNumber {
											let sourceVideoTrack = self.playerAsset!.tracks(withMediaType: AVMediaTypeVideo)[0]
											let videoDimensions = CMVideoFormatDescriptionGetDimensions(sourceVideoTrack.formatDescriptions[0] as! CMVideoFormatDescription)
											if let videoOrientation = CGImagePropertyOrientation(rawValue: videoOrientationValue.uint32Value) {
												let orientationTransform = self.affineTransform(for:videoOrientation, with:videoDimensions)
												let rotationTransform = CATransform3DMakeAffineTransform(orientationTransform)
												
												// Remove faceBoxes before applying transform and then re-draw them as we get new face coordinates.
												self.removeAllSublayers(from: self.facesLayer)
												self.playerLayer?.transform = rotationTransform
												self.playerLayer?.frame = self.playerView.layer.bounds
											}
										}
									}
									
								case AVMetadataIdentifierQuickTimeMetadataLocationISO6709:
									if itemDataType == String(kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709) {
										if let itemValue = metdataItem.value as? String {
											self.locationOverlayLabel.text = itemValue
										}
									}
									
								default:
									print("Timed metadata: unrecognized metadata identifier \(itemIdentifier)")
							}
						}
						
						if faces.count > 0 {
							self.drawFaceMetadataRects(faces)
						}
					}
				}
			}
		}
	}
	
	private func track(_ track: AVAssetTrack, hasMetadataIdentifier metadataIdentifier: String) -> Bool {
		let formatDescription = track.formatDescriptions[0] as! CMFormatDescription
		if let metadataIdentifiers = CMMetadataFormatDescriptionGetIdentifiers(formatDescription) as NSArray? {
			if metadataIdentifiers.contains(metadataIdentifier) {
				return true
			}
		}
		
		return false
	}
	
	private let facesLayer = CALayer()
	
	private func drawFaceMetadataRects(_ faces: [AVMetadataObject]) {
		guard let playerLayer = playerLayer else { return }
		
		DispatchQueue.main.async {
			
			let viewRect = playerLayer.videoRect
			self.facesLayer.frame = viewRect
			self.facesLayer.masksToBounds = true
			self.removeAllSublayers(from: self.facesLayer)
			
			for face in faces {
				let faceBox = CALayer()
				let faceRect = face.bounds
				let viewFaceOrigin = CGPoint(x: faceRect.origin.x * viewRect.size.width, y: faceRect.origin.y * viewRect.size.height)
				let viewFaceSize = CGSize(width: faceRect.size.width * viewRect.size.width, height: faceRect.size.height * viewRect.size.height)
				let viewFaceBounds = CGRect(x: viewFaceOrigin.x, y: viewFaceOrigin.y, width: viewFaceSize.width, height: viewFaceSize.height)
				
				CATransaction.begin()
				CATransaction.setDisableActions(true)
				self.facesLayer.addSublayer(faceBox)
				faceBox.masksToBounds = true
				faceBox.borderWidth = 2.0
				faceBox.borderColor = UIColor(red: CGFloat(0.3), green: CGFloat(0.6), blue: CGFloat(0.9), alpha: CGFloat(0.7)).cgColor
				faceBox.cornerRadius = 5.0
				faceBox.frame = viewFaceBounds
				CATransaction.commit()
				
				PlayerViewController.updateAnimation(for: self.facesLayer, removeAnimation: true)
			}
		}
	}
	
	@IBOutlet private weak var locationOverlayLabel: UILabel!
	
	// MARK: Animation Utilities
	
	class private func updateAnimation(for layer: CALayer, removeAnimation remove: Bool) {
		if remove {
			layer.removeAnimation(forKey: "animateOpacity")
		}
		
		if layer.animation(forKey: "animateOpacity") == nil {
			layer.isHidden = false
			let opacityAnimation = CABasicAnimation(keyPath: "opacity")
			opacityAnimation.duration = 0.3
			opacityAnimation.repeatCount = 1.0
			opacityAnimation.autoreverses = true
			opacityAnimation.fromValue = 1.0
			opacityAnimation.toValue = 0.0
			layer.add(opacityAnimation, forKey: "animateOpacity")
		}
	}
	
	private func removeAllSublayers(from layer: CALayer) {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		
		if let sublayers = layer.sublayers {
			for layer in sublayers {
				layer.removeFromSuperlayer()
			}
		}
		
		CATransaction.commit()
	}
	
	private func affineTransform(for videoOrientation: CGImagePropertyOrientation, with videoDimensions: CMVideoDimensions) -> CGAffineTransform {
		var transform = CGAffineTransform.identity
		
		// Determine rotation and mirroring from tag value.
		var rotationDegrees = 0
		var mirror = false
		
		switch videoOrientation {
			case .up:				rotationDegrees = 0;	mirror = false
			case .upMirrored:		rotationDegrees = 0;	mirror = true
			case .down:				rotationDegrees = 180;	mirror = false
			case .downMirrored:		rotationDegrees = 180;	mirror = true
			case .left:				rotationDegrees = 270;	mirror = false
			case .leftMirrored:		rotationDegrees = 90;	mirror = true
			case .right:			rotationDegrees = 90;	mirror = false
			case .rightMirrored:	rotationDegrees = 270;	mirror = true
		}
		
		// Build the affine transform.
		var angle: CGFloat = 0.0 // in radians
		var tx: CGFloat = 0.0
		var ty: CGFloat = 0.0
		
		switch rotationDegrees {
			case 90:
				angle = CGFloat(M_PI / 2.0)
				tx = CGFloat(videoDimensions.height)
				ty = 0.0
				
			case 180:
				angle = CGFloat(M_PI)
				tx = CGFloat(videoDimensions.width)
				ty = CGFloat(videoDimensions.height)
				
			case 270:
				angle = CGFloat(M_PI / -2.0)
				tx = 0.0
				ty = CGFloat(videoDimensions.width)
				
			default:
				break
		}
		
		// Rotate first, then translate to bring 0,0 to top left.
		if angle == 0.0 {	// and in this case, tx and ty will be 0.0
			transform = CGAffineTransform.identity
		}
		else {
			transform = CGAffineTransform(rotationAngle: angle)
			transform = transform.concatenating(CGAffineTransform(translationX: tx, y: ty))
		}
		
		// If mirroring, flip along the proper axis.
		if mirror {
			transform = transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
			transform = transform.concatenating(CGAffineTransform(translationX: CGFloat(videoDimensions.height), y: 0.0))
		}
		
		return transform
	}
}
