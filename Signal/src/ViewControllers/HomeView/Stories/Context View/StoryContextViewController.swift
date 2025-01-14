//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

protocol StoryContextViewControllerDelegate: AnyObject {
    func storyContextViewControllerWantsTransitionToNextContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    )
    func storyContextViewControllerWantsTransitionToPreviousContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    )
    func storyContextViewControllerDidPause(_ storyContextViewController: StoryContextViewController)
    func storyContextViewControllerDidResume(_ storyContextViewController: StoryContextViewController)
}

class StoryContextViewController: OWSViewController {
    let context: StoryContext

    weak var delegate: StoryContextViewControllerDelegate?

    private lazy var playbackProgressView = StoryPlaybackProgressView()

    private var items = [StoryItem]()
    var currentItem: StoryItem? {
        didSet {
            currentItemMediaView?.removeFromSuperview()

            if let currentItem = currentItem {
                let itemView = StoryItemMediaView(item: currentItem)
                self.currentItemMediaView = itemView
                mediaViewContainer.addSubview(itemView)
                itemView.autoPinEdgesToSuperviewEdges()
            }

            updateProgressState()
        }
    }
    var currentItemMediaView: StoryItemMediaView?

    enum LoadPosition {
        case `default`
        case newest
        case oldest
    }
    private(set) var loadPositionIfRead: LoadPosition

    required init(context: StoryContext, loadPositionIfRead: LoadPosition = .default, delegate: StoryContextViewControllerDelegate) {
        self.context = context
        self.loadPositionIfRead = loadPositionIfRead
        super.init()
        self.delegate = delegate
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetForPresentation() {
        if let currentItemMediaView = currentItemMediaView {
            // Restart playback for the current item
            currentItemMediaView.reset()
            updateProgressState()
        } else {
            // If there's an unviewed story, we always want to present that first.
            if let firstUnviewedStory = items.first(where: { item in
                guard case .incoming(_, let viewedTimestamp) = item.message.manifest else { return false }
                return viewedTimestamp == nil
            }) {
                currentItem = firstUnviewedStory
            } else {
                switch loadPositionIfRead {
                case .newest, .default:
                    currentItem = items.last
                case .oldest:
                    currentItem = items.first
                }
            }

            // For subsequent loads, use the default position.
            loadPositionIfRead = .default
        }

        playbackProgressView.alpha = 1
        closeButton.alpha = 1
    }

    func transitionToNextItem(nextContextLoadPositionIfRead: LoadPosition = .default) {
        guard let currentItem = currentItem,
              let currentItemIndex = items.firstIndex(of: currentItem),
              let itemAfter = items[safe: currentItemIndex.advanced(by: 1)] else {
                  delegate?.storyContextViewControllerWantsTransitionToNextContext(self, loadPositionIfRead: nextContextLoadPositionIfRead)
                  return
              }

        self.currentItem = itemAfter
    }

    func transitionToPreviousItem(previousContextLoadPositionIfRead: LoadPosition = .default) {
        guard let currentItem = currentItem,
              let currentItemIndex = items.firstIndex(of: currentItem),
              let itemBefore = items[safe: currentItemIndex.advanced(by: -1)] else {
                  delegate?.storyContextViewControllerWantsTransitionToPreviousContext(self, loadPositionIfRead: previousContextLoadPositionIfRead)
                  return
              }

        self.currentItem = itemBefore
    }

    private lazy var leftTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapLeft))
    private lazy var rightTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapRight))
    private lazy var pauseGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))

    private lazy var closeButton = OWSButton(imageName: "x-24", tintColor: .ows_white)

    private lazy var mediaViewContainer = UIView()
    override func viewDidLoad() {
        super.viewDidLoad()

        view.addGestureRecognizer(leftTapGestureRecognizer)
        view.addGestureRecognizer(rightTapGestureRecognizer)
        view.addGestureRecognizer(pauseGestureRecognizer)

        leftTapGestureRecognizer.delegate = self
        rightTapGestureRecognizer.delegate = self
        pauseGestureRecognizer.delegate = self
        pauseGestureRecognizer.minimumPressDuration = 0.2

        leftTapGestureRecognizer.require(toFail: pauseGestureRecognizer)
        rightTapGestureRecognizer.require(toFail: pauseGestureRecognizer)

        view.addSubview(mediaViewContainer)

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            mediaViewContainer.layer.cornerRadius = 18
            mediaViewContainer.clipsToBounds = true
        } else {
            mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .bottom)
        }

        applyConstraints()

        let spinner = UIActivityIndicatorView(style: .white)
        view.addSubview(spinner)
        spinner.autoCenterInSuperview()
        spinner.startAnimating()

        closeButton.block = { [weak self] in
            self?.dismiss(animated: true)
        }
        closeButton.setShadow()
        closeButton.imageEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 16)
        view.addSubview(closeButton)
        closeButton.autoSetDimensions(to: CGSize(square: 56))
        closeButton.autoPinEdge(toSuperviewSafeArea: .top)
        closeButton.autoPinEdge(toSuperviewSafeArea: .leading)

        view.addSubview(playbackProgressView)
        playbackProgressView.autoPinEdge(.leading, to: .leading, of: mediaViewContainer, withOffset: OWSTableViewController2.defaultHOuterMargin)
        playbackProgressView.autoPinEdge(.trailing, to: .trailing, of: mediaViewContainer, withOffset: -OWSTableViewController2.defaultHOuterMargin)
        playbackProgressView.autoPinEdge(.bottom, to: .bottom, of: mediaViewContainer, withOffset: -OWSTableViewController2.defaultHOuterMargin)
        playbackProgressView.autoSetDimension(.height, toSize: 2)
        playbackProgressView.isUserInteractionEnabled = false

        loadStoryItems { [weak self] storyItems in
            // If there are no stories for this context, dismiss.
            guard !storyItems.isEmpty else {
                self?.dismiss(animated: true)
                return
            }

            UIView.animate(withDuration: 0.2) {
                spinner.alpha = 0
            } completion: { _ in
                spinner.stopAnimating()
                spinner.removeFromSuperview()
            }

            self?.items = storyItems
            self?.resetForPresentation()
        }
    }

    private static let maxItemsToRender = 100
    private func loadStoryItems(completion: @escaping ([StoryItem]) -> Void) {
        var storyItems = [StoryItem]()
        databaseStorage.asyncRead { [weak self] transaction in
            guard let self = self else { return }
            StoryFinder.enumerateStoriesForContext(self.context, transaction: transaction) { message, stop in
                guard let storyItem = self.buildStoryItem(for: message, transaction: transaction) else { return }
                storyItems.append(storyItem)
                if storyItems.count >= Self.maxItemsToRender { stop.pointee = true }
            }

            DispatchQueue.main.async {
                completion(storyItems)
            }
        }
    }

    private func buildStoryItem(for message: StoryMessage, transaction: SDSAnyReadTransaction) -> StoryItem? {
        switch message.attachment {
        case .file(let attachmentId):
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for StoryMessage with timestamp \(message.timestamp)")
                return nil
            }
            if let attachment = attachment as? TSAttachmentPointer {
                return .init(message: message, attachment: .pointer(attachment))
            } else if let attachment = attachment as? TSAttachmentStream {
                return .init(message: message, attachment: .stream(attachment))
            } else {
                owsFailDebug("Unexpected attachment type \(type(of: attachment))")
                return nil
            }
        case .text(let attachment):
            return .init(message: message, attachment: .text(attachment))
        }
    }

    private var pauseTime: CFTimeInterval?
    private var lastTransitionTime: CFTimeInterval?
    private static let transitionDuration: CFTimeInterval = 5
    private func updateProgressState() {
        lastTransitionTime = CACurrentMediaTime()
    }

    @objc
    func displayLinkStep(_ displayLink: CADisplayLink) {
        AssertIsOnMainThread()
        playbackProgressView.numberOfItems = items.count
        if let currentItemView = currentItemMediaView, let idx = items.firstIndex(of: currentItemView.item) {
            // When we present a story, mark it as viewed if it's not already.
            if !currentItemView.isDownloading, case .incoming(_, let viewedTimestamp) = currentItemView.item.message.manifest, viewedTimestamp == nil {
                databaseStorage.write { transaction in
                    currentItemView.item.message.markAsViewed(at: Date.ows_millisecondTimestamp(), circumstance: .onThisDevice, transaction: transaction)
                }
            }

            currentItemView.updateTimestampText()
            if currentItemView.isDownloading {
                lastTransitionTime = CACurrentMediaTime()
                playbackProgressView.itemState = .init(index: idx, value: 0)
            } else if let lastTransitionTime = lastTransitionTime {
                let currentTime: CFTimeInterval
                if let elapsedTime = currentItemView.elapsedTime {
                    currentTime = lastTransitionTime + elapsedTime
                } else {
                    currentTime = displayLink.targetTimestamp
                }

                let value = currentTime.inverseLerp(
                    lastTransitionTime,
                    (lastTransitionTime + currentItemView.duration),
                    shouldClamp: true
                )
                playbackProgressView.itemState = .init(index: idx, value: value)

                if value >= 1 {
                    transitionToNextItem()
                }
            } else {
                playbackProgressView.itemState = .init(index: idx, value: 0)
            }
        } else {
            playbackProgressView.itemState = .init(index: 0, value: 0)
        }
    }

    private lazy var iPhoneConstraints = [
        mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .top),
        mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .leading),
        mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .trailing)
    ]

    private lazy var iPadConstraints: [NSLayoutConstraint] = {
        var constraints = mediaViewContainer.autoCenterInSuperview()

        // Prefer to be as big as possible.
        let heightConstraint = mediaViewContainer.autoMatch(.height, to: .height, of: view)
        heightConstraint.priority = .defaultHigh
        constraints.append(heightConstraint)

        let widthConstraint = mediaViewContainer.autoMatch(.width, to: .width, of: view)
        widthConstraint.priority = .defaultHigh
        constraints.append(widthConstraint)

        return constraints
    }()

    private lazy var iPadLandscapeConstraints = [
        mediaViewContainer.autoMatch(
            .height,
            to: .height,
            of: view,
            withMultiplier: 0.75,
            relation: .lessThanOrEqual
        )
    ]
    private lazy var iPadPortraitConstraints = [
        mediaViewContainer.autoMatch(
            .height,
            to: .height,
            of: view,
            withMultiplier: 0.65,
            relation: .lessThanOrEqual
        )
    ]

    private func applyConstraints(newSize: CGSize = CurrentAppContext().frame.size) {
        NSLayoutConstraint.deactivate(iPhoneConstraints)
        NSLayoutConstraint.deactivate(iPadConstraints)
        NSLayoutConstraint.deactivate(iPadPortraitConstraints)
        NSLayoutConstraint.deactivate(iPadLandscapeConstraints)

        if UIDevice.current.isIPad {
            NSLayoutConstraint.activate(iPadConstraints)
            if newSize.width > newSize.height {
                NSLayoutConstraint.activate(iPadLandscapeConstraints)
            } else {
                NSLayoutConstraint.activate(iPadPortraitConstraints)
            }
        } else {
            NSLayoutConstraint.activate(iPhoneConstraints)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.applyConstraints(newSize: size)
        } completion: { _ in
            self.applyConstraints()
        }
    }
}

extension StoryContextViewController: UIGestureRecognizerDelegate {
    @objc
    func didTapLeft() {
        guard currentItemMediaView?.willHandleTapGesture(leftTapGestureRecognizer) != true else { return }
        CurrentAppContext().isRTL
            ? transitionToNextItem(nextContextLoadPositionIfRead: .oldest)
            : transitionToPreviousItem(previousContextLoadPositionIfRead: .newest)
    }

    @objc
    func didTapRight() {
        guard currentItemMediaView?.willHandleTapGesture(rightTapGestureRecognizer) != true else { return }
        CurrentAppContext().isRTL
            ? transitionToPreviousItem(previousContextLoadPositionIfRead: .newest)
            : transitionToNextItem(nextContextLoadPositionIfRead: .oldest)
    }

    @objc
    func handleLongPress() {
        switch pauseGestureRecognizer.state {
        case .began:
            pauseTime = CACurrentMediaTime()
            delegate?.storyContextViewControllerDidPause(self)
            currentItemMediaView?.pause {
                self.playbackProgressView.alpha = 0
                self.closeButton.alpha = 0
            }
        case .ended:
            if let lastTransitionTime = lastTransitionTime, let pauseTime = pauseTime {
                let pauseDuration = CACurrentMediaTime() - pauseTime
                self.lastTransitionTime = lastTransitionTime + pauseDuration
                self.pauseTime = nil
            }
            currentItemMediaView?.play {
                self.playbackProgressView.alpha = 1
                self.closeButton.alpha = 1
            }
            delegate?.storyContextViewControllerDidResume(self)
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let touchLocation = gestureRecognizer.location(in: view)
        if gestureRecognizer == leftTapGestureRecognizer {
            var previousFrame = mediaViewContainer.frame
            previousFrame.width = previousFrame.width / 2
            return previousFrame.contains(touchLocation)
        } else if gestureRecognizer == rightTapGestureRecognizer {
            var nextFrame = mediaViewContainer.frame
            nextFrame.width = nextFrame.width / 2
            nextFrame.x += nextFrame.width
            return nextFrame.contains(touchLocation)
        } else {
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension StoryContextViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard var currentItem = currentItem else { return }
        guard !databaseChanges.storyMessageRowIds.isEmpty else { return }

        databaseStorage.asyncRead { transaction in
            var newItems = self.items
            var shouldDismiss = false
            for (idx, item) in self.items.enumerated().reversed() {
                guard let id = item.message.id, databaseChanges.storyMessageRowIds.contains(id) else { continue }
                if let message = StoryMessage.anyFetch(uniqueId: item.message.uniqueId, transaction: transaction) {
                    if let newItem = self.buildStoryItem(for: message, transaction: transaction) {
                        newItems[idx] = newItem

                        if item.message.uniqueId == currentItem.message.uniqueId {
                            currentItem = newItem
                        }

                        continue
                    }
                }

                newItems.remove(at: idx)
                if item.message.uniqueId == currentItem.message.uniqueId {
                    shouldDismiss = true
                    break
                }
            }
            DispatchQueue.main.async {
                if shouldDismiss {
                    self.dismiss(animated: true)
                } else {
                    self.items = newItems
                    self.currentItem = currentItem
                }
            }
        }
    }

    func databaseChangesDidUpdateExternally() {}

    func databaseChangesDidReset() {}
}
