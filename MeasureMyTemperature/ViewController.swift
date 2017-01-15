//
//  ViewController.swift
//  MeasureMyTemperature
//
//  Created by Anton Sokolchenko on 10.01.17.
//  Copyright © 2017 Sokolchenko. All rights reserved.
//

import UIKit

let knownTiles: [String: String] = ["4076B009-0455-4AF7-A705-6D4ACD45A556": "Notifications",
                                    "823BA55A-7C98-4261-AD5E-929031289C6E": "Email",
                                    "69A39B4E-084B-4B53-9A1B-581826DF9E36": "Weather"]

class ViewController: UIViewController {

	var client: MSBClient?
	
	@IBOutlet weak var statusItem: UINavigationItem!
	@IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
	@IBOutlet weak var temperatureLabel: UILabel!
	
	let tileFabric = TileFabric()
	
	
	let measuringTemperatureText = "Measuring..."
	var lastMeasureTemperature: Double?
	
	var reconnectTimer: SVTimer?
	let connectionQueue = DispatchQueue(label: "reconnectionQueue", qos: DispatchQoS.utility)
	
	override func viewDidLoad() {
		super.viewDidLoad()
		MSBClientManager.shared().delegate = self
		
		connectToBand()
		
		NotificationCenter.default.addObserver(self, selector: #selector(bluetoothStateChanged), name: NSNotification.Name.MSBClientManagerBluetoothPower, object: nil)
	}
	
	func bluetoothStateChanged(notification: Notification) {
		guard let enabled = notification.userInfo?[MSBClientManagerBluetoothPowerKey] as? NSNumber else { return }
		if enabled.boolValue {
			connectToBand()
		}
	}
	
	func connectToBand() {
		if let client = MSBClientManager.shared().attachedClients().first as? MSBClient {
			showConnectingStatus()
			self.client = client
			client.tileDelegate = self
			MSBClientManager.shared().connect(client)
		}else {
			NSLog("%@", "No attached clients")
			if let reconnectTimer = reconnectTimer {
				if reconnectTimer.isValid {
					return
				}
			}
			reconnectTimer?.cancel()
			reconnectTimer = nil
			
			NSLog("%@", "Reconnect timer started")
			reconnectTimer = SVTimer(interval: 1000, tolerance: 1000, repeats: true, queue: connectionQueue, block: { [weak self] in
				guard let strongSelf = self else { return }
				
				if MSBClientManager.shared().attachedClients().count > 0 {
					strongSelf.connectToBand()
					strongSelf.reconnectTimer?.cancel()
					strongSelf.reconnectTimer = nil
					NSLog("%@", "Reconnect timer dealloc")
				}
			})
			reconnectTimer?.start()
		}
	}
	
	// MARK: - Connection status
	func showConnectingStatus() {
		activityIndicatorView.startAnimating()
		statusItem.title = "Connecting..."
	}
	
	func showConnectedStatusFor(clientName: String) {
		activityIndicatorView.stopAnimating()
		statusItem.title = "Connected to " + clientName
	}
	
	func showDisconnectedStatusFor(clientName: String) {
		activityIndicatorView.stopAnimating()
		statusItem.title = "Disconnected from " + clientName
	}
	
	func showFailedStatusFor(clientName: String) {
		activityIndicatorView.stopAnimating()
		statusItem.title = "Failed to connect to " + clientName
	}
	
	func showCannotRetrieveStatus() {
		activityIndicatorView.stopAnimating()
		statusItem.title = "Can not retrieve tiles"
	}
	
	// MARK: - Measure notifications tile adding to Microsoft Band 2 strip
	
	@IBAction func removeMeasureTile(_ sender: UIButton) {
		client?.tileManager.removeTile(with: UUID(uuidString: tileFabric.measureTileID), completionHandler: { [weak self] (error) in
			if error == nil {
				self?.show(notificationMessage: "Removed", withTitle: "Success")
			} else {
				self?.show(notificationMessage: "Can not remove the tile", withTitle: "Error")
			}
		})
	}
	
	@IBAction  func addMeasureTileToBand(_ sender: UIButton) {
		guard let measureTile = tileFabric.measureTile() else {
			show(notificationMessage: "Can not create a tile", withTitle: "Error")
			return
		}
		
		client?.tileManager.add(measureTile, completionHandler: { [weak self] (error) in
			guard let strongSelf = self else { return }
			
			if error == nil {
				strongSelf.updateMeasureTileWithText(text: strongSelf.measuringTemperatureText)
			} else if let error = error as? NSError {
				if error.code == MSBErrorType.tileAlreadyExist.rawValue {
					strongSelf.updateMeasureTileWithText(text: strongSelf.measuringTemperatureText)
				} else {
					strongSelf.show(notificationMessage: "Can not create a tile on Band", withTitle: "Error")
				}
			}
		})
	}
	
	func updateMeasureTileWithText(text: String) {
		NSLog("%@", "Updating measure tile")
		
		let textData = try! MSBPageWrappedTextBlockData(elementId: 1, text: text)
		
		let pageData = MSBPageData(id: UUID(uuidString: tileFabric.measureTilepageDataID), layoutIndex: 0, value: [textData])
		
		client?.tileManager.setPages([pageData as Any], tileId: UUID(uuidString: tileFabric.measureTileID), completionHandler: { [weak self] (error) in
			if error == nil {
				NSLog("%@", "Measure tile sent successfully text: \(text)")
			} else {
				self?.show(notificationMessage: "Error sending tile information", withTitle: "Error")
			}
		})
	}
	
	// MARK: - Actions
	
	func show(notificationMessage: String, withTitle title: String) {
		let controller = UIAlertController(title: title, message: notificationMessage, preferredStyle: .alert)
		let okAction = UIAlertAction(title: "Ok", style: .default, handler: nil)
		controller.addAction(okAction)
		present(controller, animated: true, completion: nil)
	}

	// MARK: - Tiles loading
	func measureTemperature() {
		let temperatureInfo = measureTextWithCurrentTemperature(currentTemperature: nil)
		self.temperatureLabel.text = temperatureInfo
		updateMeasureTileWithText(text: temperatureInfo)
		do{
			try client?.sensorManager.startSkinTempUpdates(to: OperationQueue.main, withHandler: { [weak self] (skinTemperatureData, error) in
				guard let strongSelf = self else { return }
				
				var result = "Error measuring temperature"
				
				if let temperature = skinTemperatureData?.temperature {
					result = strongSelf.measureTextWithCurrentTemperature(currentTemperature: temperature)
					strongSelf.lastMeasureTemperature = temperature
				} else {
					result += strongSelf.measureTextWithCurrentTemperature(currentTemperature: nil)
				}
				
				strongSelf.temperatureLabel.text = result
				strongSelf.updateMeasureTileWithText(text: result)
				
				try? strongSelf.client?.sensorManager.stopSkinTempUpdatesErrorRef()
			})
		} catch let error {
			NSLog("%@", "Error measuring temperature \(error)")
		}
	}
	
	func measureTextWithCurrentTemperature(currentTemperature: Double?) -> String {
		var temperatureInfo = measuringTemperatureText
		if let temperature = currentTemperature {
			temperatureInfo = "\(temperature) °С"
		}
		if let lastMeasuredTemperature = lastMeasureTemperature {
			temperatureInfo += "\nPrevious: \(lastMeasuredTemperature) °С"
		}
		return temperatureInfo
	}
}

extension ViewController: MSBClientManagerDelegate {
	func clientManager(_ clientManager: MSBClientManager!, clientDidConnect client: MSBClient!) {
		NSLog("%@", "clientDidConnect")
		showConnectedStatusFor(clientName: client.name)
		measureTemperature()
	}
	
	func clientManager(_ clientManager: MSBClientManager!, clientDidDisconnect client: MSBClient!) {
		NSLog("%@", "clientDidDisconnect")
		showDisconnectedStatusFor(clientName: client.name)
	}
	
	func clientManager(_ clientManager: MSBClientManager!, client: MSBClient!, didFailToConnectWithError error: Error!) {
		NSLog("%@", "didFailToConnectWithError")
		showFailedStatusFor(clientName: client.name)
	}
}

extension ViewController: MSBClientTileDelegate {
	func client(_ client: MSBClient!, tileDidOpen event: MSBTileEvent!) {
		NSLog("%@", "tileDidOpen \(event)")
		measureTemperature()
	}
	
	func client(_ client: MSBClient!, tileDidClose event: MSBTileEvent!) {
		NSLog("%@", "tileDidClose \(event)")
	}
}
