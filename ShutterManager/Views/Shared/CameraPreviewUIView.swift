//
//  CameraPreviewUIView.swift
//  ShutterManager
//
//  Shows the camera's shared preview layer. The barcode scanner and the light meter both use it.
//

import UIKit
import AVFoundation

/// Hosts the camera's preview layer. The layer is shared, so it's shown by one view at a time:
/// the last to `attach` it. A view whose layer was taken leaves it alone until it attaches it again.
class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// The preview layer, while this view is the one showing it.
    private var shownLayer: AVCaptureVideoPreviewLayer? {
        previewLayer?.superlayer === layer ? previewLayer : nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A standalone sublayer animates frame changes implicitly; track the view's bounds exactly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shownLayer?.frame = bounds
        CATransaction.commit()
    }

    /// Installs the shared preview layer, taking it from any other view showing the camera.
    /// Attaching the layer this view already shows is a no-op.
    func attach(_ layer: AVCaptureVideoPreviewLayer?) {
        guard let layer, layer.superlayer !== self.layer else { return }
        if previewLayer !== layer { previewLayer?.removeFromSuperlayer() }
        self.layer.addSublayer(layer)   // also removes it from any previous superlayer
        previewLayer = layer
        setNeedsLayout()
    }

    /// Shows the preview only while the session is ready, so a stopped or reconfiguring session
    /// shows black rather than a frozen frame. Cheap: no layer is created or removed.
    func setPreviewVisible(_ visible: Bool) {
        guard let previewLayer = shownLayer, previewLayer.isHidden == visible else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.isHidden = !visible
        CATransaction.commit()
    }
}
