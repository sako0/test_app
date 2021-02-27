require 'net/https'
require 'open-uri'
require 'mechanize'
require 'selenium-webdriver'
require 'capybara'
require 'capybara/dsl'
require "aws-sdk"

Capybara.configure do |config|
  config.server_host = :host
  config.javascript_driver = :remote_chrome
end

Capybara.register_driver :remote_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new

  options.add_argument('--no-sandbox')
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--window-size=1680,1050')

  Aws.config[:region] = "ap-northeast-1" # AP対応まだです?
  Aws.config[:access_key_id] = ENV['ACCESS_KEY_ID']
  Aws.config[:secret_access_key] = ENV['SECRET_ACCESS_KEY']

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options,
    url: "http://chrome:4444/wd/hub",
  )
end
Capybara.javascript_driver = :remote_chrome

class Api::V1::TinderController < ApplicationController
  include Capybara::DSL

  def new
    aaa = "https://www.facebook.com/v3.2/dialog/oauth?redirect_uri=fb464891386855067%3A%2F%2Fauthorize%2F&scope=user_birthday%2Cuser_photos%2Cuser_education_history%2Cemail%2Cuser_relationship_details%2Cuser_friends%2Cuser_work_history%2Cuser_likes&response_type=token%2Csigned_request&client_id=464891386855067&ret=login&fallback_redirect_uri=221e1158-f2e9-1452-1a05-8983f99f7d6e&ext=1556057433&hash=Aea6jWwMP_tDMQ9y"
    start_scraping aaa do
      # ここにスクレイピングのコードを書く
      fill_in "email", with: ENV['FB_EMAIL']
      fill_in "pass", with: ENV['FB_PASS']
      if has_button?("Accept All")
        click_button('Accept All')
      else
        click_button('すべて許可')
      end
      find("#loginbutton").click
      click_button('OK')
      access_token_html = html
      p html
      str = access_token_html.to_s
      idx = str.index("&access_token=")
      end_idx = str.index("&data_access_expiration_time=")
      @@access_token = str.slice(idx + 14..end_idx - 1)
      p @@access_token
    end
    # FBトークンからTinderのトークンを取得
    uri = URI.parse("https://api.gotinder.com/v2/auth/login/facebook")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Post.new(uri.path)
    post_data = { 'facebook_id' => ENV['FB_ID'], 'token' => @@access_token }.to_json
    req.body = post_data
    res = http.request(req)
    api_response = JSON.parse(res.body)
    p api_response
    tinder_token = api_response['data']['api_token']
    render json: tinder_token
  end

  def index
    uri = URI.parse('https://api.gotinder.com/user/recs')
    api_headers = {
      'X-Auth-Token' => '999f6ab2-2ce2-48f3-a4a9-be8cdc5517fa',
      'Content-type' => 'application/json',
      'User-agent' => 'Tinder/3.0.4 (iPhone; iOS 7.1; Scale/2.00)'
    }
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = http.get(uri.path, api_headers)
    res_body = JSON.parse(res.body)
    res_body['results'].each do |result|
      get_image(result['photos'][0]['processedFiles'][0]['url'], result['photos'][0]['id'])
    end
    render json: res_body
  end

  private

  # URLを対象にウェブサイトのスクレイピングを行う
  def start_scraping(url, &block)
    Capybara::Session.new(:remote_chrome).tap { |session|
      session.visit url
      session.instance_eval(&block)
    }
  end

  # 画像をローカルに保存する
  def get_image(url, prefix)
    prefix_str = prefix.to_s
    file = '/myapp/images/' + prefix_str + '.jpg'
    # 取得した画像URLから画像をダウンロードする
    File.open(file, 'w+b') do |pass|
      OpenURI.open_uri(url) do |recieve|
        pass.write(recieve.read)
      end
    end
  end
end

