import UIKit


final class ViewController: UIViewController {
    var mainViewModel: MainViewModelProtocol = MainViewModel()

    private lazy var playerContainerView: UILabel = {
        let playerContainerView = UILabel()
        playerContainerView.backgroundColor = .clear
        playerContainerView.textAlignment = .center
        view.addSubview(playerContainerView)
        playerContainerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        playerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        playerContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        playerContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        return playerContainerView
    }()

    private lazy var playerView: PlayerView = {
        let playerView = PlayerView()
        playerContainerView.addSubview(playerView)

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.leadingAnchor.constraint(equalTo: playerContainerView.leadingAnchor).isActive = true
        playerView.trailingAnchor.constraint(equalTo: playerContainerView.trailingAnchor).isActive = true
        playerView.bottomAnchor.constraint(equalTo: playerContainerView.safeAreaLayoutGuide.bottomAnchor).isActive = true
        playerView.topAnchor.constraint(equalTo: playerContainerView.safeAreaLayoutGuide.topAnchor).isActive = true

        return playerView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    func bind() {
        mainViewModel.start()

        mainViewModel.onUpdate = { [weak self] loadingStatus in
            DispatchQueue.main.async {
                self?.playerContainerView.text = loadingStatus
            }
        }

        mainViewModel.onShow = { [weak self] url in
            DispatchQueue.main.async {
                self?.playerView.play(with: url)
            }
        }
    }
}

