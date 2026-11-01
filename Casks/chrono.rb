cask "chrono" do
  version "1.0.0"
  sha256 "06ba27143a1b994829f5df2255d7bd7664767c78ff2f83f42a94a857c8f3bf03"

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
