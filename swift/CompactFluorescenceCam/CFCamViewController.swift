//
//  CFCamViewController.swift
//  CompactFluorescenceCam
//
//  If you find this code useful please cite the following:
//
//  @article{hunt_ultracompact_2021,
//                title = {Ultracompact fluorescence smartphone attachment using built-in optics for protoporphyrin-{IX} quantification in skin},
//                issn = {2156-7085, 2156-7085},
//                url = {https://www.osapublishing.org/boe/abstract.cfm?doi=10.1364/BOE.439342},
//                doi = {10.1364/BOE.439342},
//                language = {en},
//                urldate = {2021-10-18},
//                journal = {Biomedical Optics Express},
//                author = {Hunt, Brady and Streeter, Samuel and Ruiz, Alberto and Chapman, M. Shane and Pogue, Brian},
//                month = oct,
//                year = {2021},
//            }
// CFCamViewController is adapted from Apple's AVCam example Swift application:
// https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/avcam_building_a_camera_app

import UIKit
import Combine
import AVFoundation

class CFCamViewController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var activeDevice: AVCaptureDevice?
    var wideDevice: AVCaptureDevice?
    var ultrawideDevice: AVCaptureDevice?
    var teleDevice: AVCaptureDevice?
    var videoDeviceInput: AVCaptureDeviceInput!
    var format: AVCaptureDevice.Format!
    
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var lockImageView: UIImageView!
    @IBOutlet weak var exposureDurationSlider: UISlider!
    @IBOutlet weak var isoSlider: UISlider!
    @IBOutlet weak var torchSlider: UISlider!
    @IBOutlet weak var exposureDurationLabel: UILabel!
    @IBOutlet weak var isoLabel: UILabel!
    @IBOutlet weak var torchLabel: UILabel!
    @IBOutlet weak var cameraPicker: UIPickerView!
    @IBOutlet weak var roiAvgLabel: UILabel!
    
    var hideableUIViews: [UIView] = []
    var controlsLocked = false
    var cameraPickerData: [String] = ["Wide","Ultra-wide","Telephoto"]
        
    let session = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let sessionQueue = DispatchQueue(label: "session queue")
    let videoBufferQueue = DispatchQueue(label: "video buffer Queue")
    
    enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    var setupResult: SessionSetupResult = .success
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // UI controls locked on launch.
        hideableUIViews = [exposureDurationSlider, isoSlider, torchSlider, exposureDurationLabel, isoLabel, torchLabel, cameraPicker]
        lockUIControls()
        
        let defaultRow = cameraPickerData.firstIndex(of: "Ultra-wide")
        cameraPicker.selectRow(defaultRow!, inComponent: 0, animated: false)
        cameraPicker.reloadAllComponents()
        
        // Set up the video preview view.
        previewView.session = session
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Previously granted access to the camera.
            break
            
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        sessionQueue.async {
            self.initializeSession()
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let currExposure = exposureDurationSlider.value
        let currISO = isoSlider.value
        let currTorchLevel = torchSlider.value

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.session.startRunning()
                let device = self.videoDeviceInput.device
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = self.format
                    device.unlockForConfiguration()
                } catch {
                    print("Session configuration failed: \(error)")
                }
                self.configureSession(exposure: currExposure, iso: currISO, torchLevel: currTorchLevel)

            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "App doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "CF-Cam", message: message, preferredStyle: .alert)

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                  options: [:],
                                                  completionHandler: nil)
                    }))

                    self.present(alertController, animated: true, completion: nil)
                }

            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Error initializing camera."
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "CF-Cam", message: message, preferredStyle: .alert)

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))

                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    func initializeSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // Add video input
        do {
            
            // Get default devices for ultrawide, wide, and tele
            self.ultrawideDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            self.wideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            self.teleDevice = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
            
            // Choose the back ultrawide camera, if available, otherwise default to a wide angle camera.
            if let ultrawideDevice = self.ultrawideDevice {
                self.activeDevice = ultrawideDevice
            } else if let wideDevice = self.wideDevice {
                self.activeDevice = wideDevice
            } else if let teleDevice = self.teleDevice {
                self.activeDevice = teleDevice
            }
            
            guard let videoDevice = self.activeDevice else {
                print("Requested video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
                        
            // Look for 10-bit 'x420' video format
            let deviceFormats = videoDevice.formats
            let x420PixelFormat = deviceFormats.first { format in
                let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
                return pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange // 2016686640, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            }
            
            if let format = x420PixelFormat {
                self.format = format
                
            } else {
                fatalError("10-bit video format not found.")
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add video output
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: videoBufferQueue)
            
        } else {
            print("Could not add video output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        
    }
    
    func configureSession(exposure:Float, iso:Float, torchLevel:Float) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                if device.isExposureModeSupported(.custom) {
                    let exposureTime = CMTimeMakeWithSeconds(Float64(exposure), preferredTimescale: 1000000)
                    device.setExposureModeCustom(duration: exposureTime, iso: iso, completionHandler: nil)
                } else {
                    fatalError("Custom exposure not supported")
                }
                
                if device.isTorchModeSupported(.on) {
                    if torchLevel > 0 {
                        try device.setTorchModeOn(level: torchLevel)
                    } else {
                        device.torchMode = .off
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Session configuration failed: \(error)")
            }
        }
        
    }
    
    @IBAction func lockButtonTapped(_ sender: Any) {
        if controlsLocked {
            unlockUIControls()
        } else {
            lockUIControls()
        }
    }
    
    @IBAction func controlSettingsChanged(_ sender: UISlider?) {
        
        // rebound ISO controls
        let minISO = self.videoDeviceInput.device.activeFormat.minISO
        let maxISO = self.videoDeviceInput.device.activeFormat.maxISO
        
        let currISO = isoSlider.value
        isoSlider.minimumValue = minISO
        isoSlider.maximumValue = maxISO
        
        if currISO < minISO {
            isoSlider.value = minISO
        } else if currISO > maxISO {
            isoSlider.value = maxISO
        }
        
        // get new values
        let newExposureDuration = (exposureDurationSlider.value * 1000).rounded() / 1000
        let newISO = isoSlider.value.rounded()
        let newTorchLevel = (torchSlider.value * 100).rounded() / 100
        
        // configure session
        self.configureSession(exposure: newExposureDuration, iso: newISO, torchLevel: newTorchLevel)
        
        // update labels
        isoLabel.text = String(Int(newISO))
        exposureDurationLabel.text = String(Int(newExposureDuration*1000)) + "ms"
        torchLabel.text = String(Int(newTorchLevel*100)) + "%"
        
        // update label positions
        let exposureDurationTrackRect = exposureDurationSlider.trackRect(forBounds: exposureDurationSlider.frame)
        let exposureDurationThumbRect = exposureDurationSlider.thumbRect(forBounds: exposureDurationSlider.bounds, trackRect: exposureDurationTrackRect, value: exposureDurationSlider.value)
        self.exposureDurationLabel.center = CGPoint(x: exposureDurationThumbRect.midX, y: self.exposureDurationLabel.center.y)
        
        let isoTrackRect = isoSlider.trackRect(forBounds: isoSlider.frame)
        let isoThumbRect = isoSlider.thumbRect(forBounds: isoSlider.bounds, trackRect: isoTrackRect, value: isoSlider.value)
        self.isoLabel.center = CGPoint(x: isoThumbRect.midX, y: self.isoLabel.center.y)
        
        let torchTrackRect = torchSlider.trackRect(forBounds: torchSlider.frame)
        let torchThumbRect = torchSlider.thumbRect(forBounds: torchSlider.bounds, trackRect: torchTrackRect, value: torchSlider.value)
        self.torchLabel.center = CGPoint(x: torchThumbRect.midX, y: self.torchLabel.center.y)
    }
    
    func lockUIControls() {
        
        for view in hideableUIViews {
            view.isHidden = true
        }
        
        lockImageView.image = UIImage(systemName: "lock.fill")
        controlsLocked = true
        
    }
    
    func unlockUIControls() {
        
        for view in hideableUIViews {
            view.isHidden = false
        }
        
        lockImageView.image = UIImage(systemName: "lock.open.fill")
        controlsLocked = false
    }
    
    private var wrongBufferCount = 0
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
                
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { fatalError("buffer not available.") }
        
        // Check that video buffer was succesfully initialized to 10-bit format
        if ( CVPixelBufferGetPixelFormatType(buffer) != 2016686640 ) {
            wrongBufferCount += 1
            if wrongBufferCount > 100 {
                fatalError("Video buffer did not initialize properly")
            }
        } else {
            wrongBufferCount = 0
        }
        
        // Calculate average intensity from centeral ROI
        // read CVPixelBuffer to numerical array adapted from Stack Overflow examples:
        // https://stackoverflow.com/a/57993883, https://stackoverflow.com/a/65210114
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let midX = Int(width/2) - 1
        let midY = Int(height/2) - 1
        let xOffset = 100
        let yOffset = 100
        let startX = midX - xOffset
        let startY = midY - yOffset
        let endX = startX + xOffset
        let endY = startY + yOffset
        
        // lock base addresss before accessing
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        // YUV420 format is BiPlanar with first plane corresponding to Luma (Y) and second plane corresponding to lower resolution Chroma buffer
        let LUMA_PLANE_INDEX = 0
        let baseAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, LUMA_PLANE_INDEX)!
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, LUMA_PLANE_INDEX)
        var intensityTotal:Float32 = 0.0
        var valCount = 0
        for x in startX..<endX {
            for y in startY..<endY {
                let rowData = baseAddress + x * bytesPerRow
                let intensity = rowData.assumingMemoryBound(to: UInt16.self)[y]
                intensityTotal += Float(intensity)
                valCount += 1
            }
        }
        
        let intensityAvg = intensityTotal/(Float(valCount))
        
        DispatchQueue.main.async {
            let avgRenormalized = (Int(intensityAvg/(4*10))*10 - 1020) // ranges from 0 to 13,400
            self.roiAvgLabel.text = "ROI Avg: " + String(avgRenormalized)
        }

    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return 3
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if cameraPickerData.indices.contains(row) {
            return cameraPickerData[row]
        } else {
            return nil
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let value = cameraPickerData[row]
        if value == "Wide"{
            print("Wide selected")
            self.activeDevice = self.wideDevice
            resetVideoInput()
        } else if value == "Ultra-wide" {
            print("Ultra-wide selected")
            self.activeDevice = self.ultrawideDevice
            resetVideoInput()
        } else {
            print("Tele selected")
            self.activeDevice = self.teleDevice
            resetVideoInput()
        }
    }
    
    func resetVideoInput() {
        
        let currExposure = exposureDurationSlider.value
        var currISO = isoSlider.value
        let currTorchLevel = torchSlider.value

        sessionQueue.async {
            
            if let videoDevice = self.activeDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        fatalError("Could not add video input.")
                    }
                    
                    self.session.commitConfiguration()
                    
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
        }
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            
            // Look for 10-bit 'x420' video format
            let deviceFormats = device.formats
            let x420PixelFormat = deviceFormats.first { format in
                let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
                return pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange // 2016686640, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            }
            
            if let format = x420PixelFormat {
                self.format = format
                
            } else {
                fatalError("10-bit video format not found.")
            }
            
            do {
                try device.lockForConfiguration()
                device.activeFormat = self.format
                device.unlockForConfiguration()
            } catch {
                print("Session configuration failed: \(error)")
            }
            
            // rebound ISO controls
            let minISO = device.activeFormat.minISO
            let maxISO = device.activeFormat.maxISO
            
            if currISO < minISO {
                currISO = minISO
            } else if currISO > maxISO {
                currISO = maxISO
            }
            
            self.configureSession(exposure: currExposure, iso: currISO, torchLevel: currTorchLevel)
        }
    }
    
    
//    func resetISO() {
//
//        let minISO = activeDevice!
//        let maxISO = defaultDevice!.validISOValues!.upperBound
//
//        let currISO = isoSlider.value
//        isoSlider.minimumValue = minISO
//        isoSlider.maximumValue = maxISO
//
//        if currISO < minISO {
//            isoSlider.value = minISO
//        } else if currISO > maxISO {
//            isoSlider.value = maxISO
//        }
//
//        self.exposureChanged(isoSlider)
//        let newExposure = ImagingCaptureSettings.Exposure(duration: exposureDurationSlider.value, iso: isoSlider.value)
//        captureSettings = ImagingCaptureSettings(exposure: newExposure, torchLevel: torchSlider.value)
        
//    }
    //
    //        func setupWide() {
    //            defaultDevice = wideDevice
    //            resetISO()
    //            imagingDevicePreviewView.showPreview(device: defaultDevice!,
    //                                                 session: imagingSession,
    //                                                 settings: captureSettings)
    //        }
    //
    //        func setupUltrawide() {
    //            defaultDevice = ultrawideDevice
    //            resetISO()
    //            imagingDevicePreviewView.showPreview(device: defaultDevice!,
    //                                                 session: imagingSession,
    //                                                 settings: captureSettings)
    //        }
    //
    //        func setupTele() {
    //            defaultDevice = teleDevice
    //            resetISO()
    //            imagingDevicePreviewView.showPreview(device: defaultDevice!,
    //                                                 session: imagingSession,
    //                                                 settings: captureSettings)
    //        }
    
}

