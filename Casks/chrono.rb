cask "chrono" do
  version "1.2.0"
  sha256 "54fa476d4d6f678e565e1b6f0f6f402c5a9602bcb646d8f0a93129adb69ade4e"

  url "https://github.com/torresrobert/chrono/releases/download/v#{version}/Chrono-#{version}.zip"
  name "Chrono"
  desc "Menu bar system monitor with a terminal view"
  homepage "https://github.com/torresrobert/chrono"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Chrono.app"
  binary "#{appdir}/Chrono.app/Contents/MacOS/Chrono", target: "chrono"

  uninstall quit: "me.torresrobert.chrono"

  zap trash: [
    "~/Library/Application Support/me.torresrobert.chrono",
    "~/Library/Preferences/me.torresrobert.chrono.plist",
  ]
end
