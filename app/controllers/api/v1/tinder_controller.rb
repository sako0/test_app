require 'net/https'
require 'open-uri'
require 'mechanize'
require 'selenium-webdriver'
require 'capybara'
require 'capybara/dsl'
require "aws-sdk"
require 'aws-sdk-s3'
require 'line/bot'

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

  Aws.config.update({
                      credentials: Aws::Credentials.new(ENV['ACCESS_KEY_ID'], ENV['SECRET_ACCESS_KEY'])
                    })

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
  # before_action :client, only: [:callback]

  # callbackアクションのCSRFトークン認証を無効
  protect_from_forgery :except => [:callback]

  def callback
    @client ||= Line::Bot::Client.new { |config|
      config.channel_id = ENV["LINE_CHANNEL_ID"]
      config.channel_secret = ENV['LINE_CHANNEL_SECRET']
      config.channel_token = ENV['LINE_CHANNEL_TOKEN']
    }
    @body = request.body.read
    @signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless @client.validate_signature(@body, @signature)
      error 400 do
        'Bad Request'
      end
    end
    @line_header = {
      'Authorization' => "Bearer " + ENV['LINE_CHANNEL_TOKEN'],
      'Content-type' => 'application/json',
    }
    events = @client.parse_events_from(@body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event['message']['text'] == "起動"
            msg = {
              "type": "text",
              "text": "起動しましたけど？"
            }
            @client.reply_message(event['replyToken'], msg)
            index
            msg = {
              "type": "text",
              "text": "え？サーバー止まったよ？"
            }
            @client.reply_message(event['replyToken'], msg)
          end
          if event['message']['text'] == "アクセストークン"
            # msg = {
            #   "type": "text",
            #   "text": "トークン発行中だから待たれよ"
            # }
            # @client.reply_message(event['replyToken'], msg)
            if new
              msg = {
                "type": "text",
                "text": "一応トークン発行してDBに保存したよ？"
              }
              render json: :ok
            else
              msg = {
                "type": "text",
                "text": "うわミスったわごめん"
              }
              render json: "ng"
            end
            @client.reply_message(event['replyToken'], msg)
          end
        end
      end
    end
  end
end

# アクセストークンを取得する api/v1/tinder/new
def new
  begin
    facebook_url = "https://www.facebook.com/v3.2/dialog/oauth?redirect_uri=fb464891386855067%3A%2F%2Fauthorize%2F&scope=user_birthday%2Cuser_photos%2Cuser_education_history%2Cemail%2Cuser_relationship_details%2Cuser_friends%2Cuser_work_history%2Cuser_likes&response_type=token%2Csigned_request&client_id=464891386855067&ret=login&fallback_redirect_uri=221e1158-f2e9-1452-1a05-8983f99f7d6e&ext=1556057433&hash=Aea6jWwMP_tDMQ9y"
    start_scraping facebook_url do
      # ここにスクレイピングのコードを書く
      fill_in "email", with: ENV['FB_EMAIL']
      fill_in "pass", with: ENV['FB_PASS']
      save_screenshot "ss.png"
      if has_button?("Accept All")
        click_button('Accept All')
      elsif has_button?("すべて許可")
        click_button('すべて許可')
      else
        save_screenshot "ss.png"
      end
      # ログインボタンクリック
      3.times do |i|
        sleep 4
        begin
          if has_button?("loginbutton")
            click_button('loginbutton')
            save_screenshot "ss.png"
            break
          else
            click_button('Log In')
            break
          end
        rescue
          p 'waitting....'
        end
      end
      # クッキー承諾ボタンクリック
      3.times do |i|
        sleep 4
        begin
          save_screenshot "ss.png"
          click_button('OK')
          break
        rescue
          p 'waitting....'
        end
      end
      access_token_html = html
      str = access_token_html.to_s
      p str
      idx = str.index("&access_token=")
      end_idx = str.index("&data_access_expiration_time=")
      access_token = str.slice(idx + 14..end_idx - 1)
      Tinder.update(1, access_token: access_token)
      p access_token
    end
    # FBトークンからTinderのトークンを取得
    access_token = Tinder.find(1)
    uri = URI.parse("https://api.gotinder.com/v2/auth/login/facebook")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Post.new(uri.path)
    post_data = { 'facebook_id' => ENV['FB_ID'], 'token' => access_token.access_token }.to_json
    req.body = post_data
    res = http.request(req)
    api_response = JSON.parse(res.body)
    p api_response
    tinder_token = api_response['data']['api_token']
    Tinder.update(1, access_token: tinder_token)
    return true
  rescue
    return false
  end
end

# 画像比較処理ループ api/v1/tinder
def index
  i = 0
  @tinder = Tinder.find(1)
  uri = URI.parse('https://api.gotinder.com/user/recs')
  @api_headers = {
    'X-Auth-Token' => @tinder.access_token,
    'Content-type' => 'application/json',
    'User-agent' => 'Tinder/3.0.4 (iPhone; iOS 7.1; Scale/2.00)'
  }
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  loop do
    begin
      res = http.get(uri.path, @api_headers)
      res_body = JSON.parse(res.body)
      if res_body['results']
        res_body['results'].each do |result|
          file_path = result['photos'][0]['processedFiles'][0]['url']
          file_name = get_image(file_path, result['photos'][0]['id'])
          object_uploaded(file_name)
          similar = compare_images(file_name, "target1.jpg")
          if similar > 20

            # today = Date.today.strftime("%Y%m%d").to_i
            # birth_date = Date.parse(result['birth_date']).strftime("%Y%m%d").to_i
            # age_f = (today - birth_date) / 10000
            # age = age_f.to_i
            # if age < 29
            #   like_user(result['_id'])
            #   p "いいねしました => [" + result['_id'] + "] " + age.to_s + "歳"

            like_user(result['_id'])
            p "条件に一致したためいいねしました => " + result['_id'] + "  マッチ率は" + similar.to_s + "%です"
          else
            # else
            #   pass_user(result['_id'])
            #   p "pass => " + result['_id']
            pass_user(result['_id'])
            p "pass => " + result['_id']
          end
          object_delete(file_name)
        end

        # 成功したため、iを初期化する
        i = 0
      else
        if i < 20
          p "再検索します"
          p (i + 1).to_s + "回目の再検索です"
          i += 1
          sleep 30
        else
          raise
        end
      end
    rescue
      # 6回連続で失敗した場合は終了
      if i < 20
        i += 1
        p (i + 1).to_s + "回目の処理失敗です"
        retry
      else
        p i.to_s + "回処理が失敗しました。プログラムを終了します。"
        msg = {
          "type": "text",
          "text": "なんか落ちましたけど？頻繁に起こるならアクセストークンの発行をし直せば？"
        }
        @client.reply_message(event['replyToken'], msg)
        raise
      end
    end
  end

  render json: "終了"
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
  prefix_str + '.jpg'
end

# Rekognitionで画像の比較
def compare_images(src_keyname, target_keyname)
  rekog = Aws::Rekognition::Client.new(region: "ap-northeast-1", access_key_id: ENV['ACCESS_KEY_ID'],
                                       secret_access_key: ENV['SECRET_ACCESS_KEY'])
  begin
    response = rekog.compare_faces({
                                     source_image: { 's3_object': {
                                       bucket: ENV['S3_BUCKETS_NAME'],
                                       name: src_keyname,
                                     } },
                                     target_image: { 's3_object': {
                                       bucket: ENV['S3_BUCKETS_NAME'],
                                       name: target_keyname,
                                     } },
                                     similarity_threshold: 1.0
                                   })
    response['face_matches'][0]['similarity']
  rescue
    0
  end
end

# S3にuploadしローカルに一時的に保存した画像を削除する
def object_uploaded(file_name)
  s3resoruce = Aws::S3::Resource.new(
    access_key_id: ENV['ACCESS_KEY_ID'],
    secret_access_key: ENV['SECRET_ACCESS_KEY'],
    region: "ap-northeast-1",
  )
  local_file_path = '/myapp/images/' + file_name
  s3resoruce.bucket(ENV['S3_BUCKETS_NAME']).object(file_name).upload_file(local_file_path)
  File.delete(local_file_path)
  file_name
end

def object_delete(file_name)
  s3resoruce = Aws::S3::Resource.new(
    access_key_id: ENV['ACCESS_KEY_ID'],
    secret_access_key: ENV['SECRET_ACCESS_KEY'],
    region: "ap-northeast-1",
  )
  s3resoruce.bucket(ENV['S3_BUCKETS_NAME']).object(file_name).delete
end

# userにいいねを行う
def like_user(uid)
  uri = URI.parse('https://api.gotinder.com/like/' + uid)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  res = http.get(uri.path, @api_headers)
  response_body = JSON.parse(res.body)
  if response_body['match'] == true
    true
  else
    false
  end
end

# userをpassする
def pass_user(uid)
  uri = URI.parse('https://api.gotinder.com/pass/' + uid)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.get(uri.path, @api_headers)
end


