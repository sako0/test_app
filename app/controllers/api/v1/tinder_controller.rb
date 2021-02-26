require 'net/https'
require 'open-uri'
require 'mechanize'
require 'selenium-webdriver'
require 'capybara'
require 'capybara/dsl'

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
      fill_in "email", with: "yfu904@gmail.com"
      fill_in "pass", with: "04090921"
      click_button('Accept All')
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
    render json: @@access_token
  end

  private

  def start_scraping(url, &block)
    Capybara::Session.new(:remote_chrome).tap { |session|
      session.visit url
      session.instance_eval(&block)
    }
  end
end

