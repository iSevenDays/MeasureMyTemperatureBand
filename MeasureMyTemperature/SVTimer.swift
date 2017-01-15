//
//  SVTimer.swift
//  RTCDemo
//
//  Created by Anton Sokolchenko on 07.12.16.
//  Copyright © 2016 anton. All rights reserved.
//

import Foundation

class SVTimer: NSObject {
	fileprivate var timer: DispatchSourceTimer?
	fileprivate(set) var interval: Int // milliseconds
	fileprivate(set) var repeats: Bool
	fileprivate(set) var block: ()->()
	fileprivate(set) var queue: DispatchQueue
	var leeway: Int // milliseconds
	
	var isValid: Bool {
		if let timer = timer {
			return !timer.isCancelled
		}
		return false
	}
	
	/*
	* Initialize a timer
	*
	* @param interval - interval in milliseconds after wich a timer will be started,
	* if repeats - block will be called until cancelled with given time interval
	*
	* @param tolerance - a tolerance in milliseconds the fire data can deviate
	* Must be positive. Can improve battery life
	*/
	init(interval: Int, tolerance: Int, repeats: Bool, queue: DispatchQueue, block: @escaping ()->()) {
		self.interval = interval
		leeway = tolerance
		self.repeats = repeats
		self.queue = queue
		self.block = block
	}
	
	/**
	Start the timer
	The timer fires once after the specified delay plus the specified tolerance.
	*/
	func start() {
		guard timer == nil else { return } // double start
		
		timer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: 0), queue: queue)
		timer!.setEventHandler(handler: block)
		
		let interval = DispatchTimeInterval.milliseconds(self.interval)
		let leeway = DispatchTimeInterval.milliseconds(self.leeway)
		if repeats {
			timer!.scheduleRepeating(deadline: .now() + interval, interval: interval, leeway: leeway)
		} else {
			timer!.scheduleOneshot(deadline: .now() + interval, leeway: leeway)
		}
		timer!.resume()
	}
	
	/// Cancel the timer
	func cancel() {
		if let timer = timer {
			if isValid {
				timer.cancel()
			}
		}
		timer = nil
	}
	
	deinit {
		cancel()
	}
}
