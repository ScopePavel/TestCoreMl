import UIKit


final class ViewController: UIViewController {
    var mainViewModel = MainViewModel()

    private lazy var loaddingLabel: UILabel = {
        let loaddingLabel = UILabel(frame: .init(origin: .zero, size: .init(width: 500, height: 500)))
        view.addSubview(loaddingLabel)
        return loaddingLabel
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    func bind() {
        mainViewModel.start()

        mainViewModel.onUpdate = { [weak self] loadingStatus in
            DispatchQueue.main.async {
                self?.loaddingLabel.text = loadingStatus
            }
        }
    }
}

