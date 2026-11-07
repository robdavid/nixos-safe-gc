require "spec"
require "process"
require "../src/safegc"

# Reopen class and redefine private method as public to test
class SafeGC
  def run_as_command(user : String)
    previous_def
  end
end

describe SafeGC do
  it "creates run_as arguments with no optional parameters" do
    gc = SafeGC.new
    gc.run_as_command("user").should eq ["sudo","-u","user",Process.executable_path]
  end
  it "creates run_as arguments with current kernel" do
    gc = SafeGC.new
    gc.kernel = ""
    gc.run_as_command("user").should eq ["sudo","-u","user",Process.executable_path,"--keep-kernel"]
  end
  it "creates run_as arguments with specific kernel" do
    gc = SafeGC.new
    gc.kernel = "7.3.0"
    gc.run_as_command("user").should eq ["sudo","-u","user",Process.executable_path,"--keep-kernel","7.3.0" ]
  end
  it "creates run_as arguments with multiple arguments" do
    gc = SafeGC.new
    gc.kernel = "7.3.0"
    gc.generations = 3
    gc.min_time = 7.days
    gc.run_as_command("user").should eq ["sudo","-u","user",Process.executable_path,"--generations","3","--days","7","--keep-kernel","7.3.0" ]
  end
end

test_profile_history = <<-HISTORY
  Version 25 (2026-10-03):
    git+file:///home/robd/src/img-pin#packages.x86_64-linux.default: ∅ -> 0.4.2
    git+file:///home/robd/src/k8s-utils#packages.x86_64-linux.default: ∅ -> 0.0.1
    git+file:///home/robd/src/snare-pin#packages.x86_64-linux.default: ∅ -> 0.0.3

  Version 26 (2026-10-08) <- 25:
    git+file:///home/robd/src/nixos-safe-gc#packages.x86_64-linux.default: ∅ -> 0.0.1

  Version 27 (2026-10-15) <- 26:
    git+file:///home/robd/src/code-template#packages.x86_64-linux.default: ∅ -> 0.0.1

  Version 28 (2026-11-01) <- 27:
    git+file:///home/robd/src/liger#packages.x86_64-linux.default: ∅ -> 0.1.3
  HISTORY
describe ProfileHistoryItem do
  it "can parse a matching version line" do
    pi = ProfileHistoryItem.parse("Version 25 (2026-10-03):")
    pi.should_not be nil
    if pi
      pi.version.should eq 25
      pi.date.should eq Time.local(year: 2026, month: 10, day: 3)
    end
  end
  it "can parse a matching version line with parent" do
    pi = ProfileHistoryItem.parse("Version 26 (2026-10-08) <- 25:")
    pi.should_not be nil
    if pi
      pi.version.should eq 26
      pi.date.should eq Time.local(year: 2026, month: 10, day: 8)
    end
  end
  it "can parse a matching version line with ANSI color codes" do
    pi = ProfileHistoryItem.parse("Version [32;1m27[0m (2026-10-15) <- 26:")
    pi.should_not be nil
    if pi
      pi.version.should eq 27
      pi.date.should eq Time.local(year: 2026, month: 10, day: 15)
    end
  end
  it "will gracefully reject non-matching lines" do
    pi = ProfileHistoryItem.parse("git+file:///home/user/src/nixos-safe-gc#packages.x86_64-linux.default: ∅ -> 0.0.1")
    pi.should be nil
  end
end

describe ProfileHistory do
  it "will parse lines from nix profile history" do
    history = ProfileHistory.parse(test_profile_history)
    history.size.should eq 4
    last = Time.local(2026,11,2)
    history.each do |item|
      (item.date < last).should be_true
      last = item.date
    end
  end
end
