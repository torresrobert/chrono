cask "chrono" do
  version "1.1.0"
  sha256 "0f7ead3f92c7e2fc638f5c103bf110394e334cf21c46e5fda77b0015d0c076cf"

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
