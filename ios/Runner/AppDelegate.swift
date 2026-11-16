import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeFirestoreCacheFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// O cache do Firestore (conversas, perfil) fica em
  /// Library/Application Support/firestore e, por padrao, entra no backup do
  /// iCloud/iTunes. Cria o diretorio e o exclui do backup antes de o Firebase
  /// usa-lo. Melhor esforco: falha nao impede o app de abrir.
  private func excludeFirestoreCacheFromBackup() {
    let fm = FileManager.default
    guard var dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return
    }
    dir.appendPathComponent("firestore", isDirectory: true)
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try dir.setResourceValues(values)
    } catch {
      // Sem registro: nada pessoal e o app segue normalmente.
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
