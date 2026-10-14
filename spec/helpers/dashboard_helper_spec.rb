# encoding: UTF-8

require "rails_helper"

RSpec.describe DashboardHelper, type: :helper do
  it "groups referrers by host as the frontend stores them, dots swapped for underscores" do
    referrers = {
      "google_com" => 1,
      "www_google_co_in" => 1,
      "x_com" => 2,
      "t_co" => 3,
      "news_ycombinator_com" => 4,
      "l_facebook_com" => 5,
      "direct" => 6,
      "internal" => 7,
      "microsoft_com" => 8
    }

    expect(helper.referrer_groups(referrers)).to eq("Search" => 2, "Social" => 14, "Direct" => 6, "Internal" => 7, "Other sites" => 8)
  end

  it "shows stored referrer keys as hosts" do
    expect(helper.referrer_hosts("google_com" => 2, "google.com" => 1, "direct" => 3)).to eq("google.com" => 3, "direct" => 3)
  end
end
