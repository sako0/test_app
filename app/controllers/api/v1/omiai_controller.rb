class Api::V1::OmiaiController < ApplicationController
  require 'line/bot'
  require 'open-uri'
  # callbackアクションのCSRFトークン認証を無効
  protect_from_forgery :except => [:callback]

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_id = ENV["LINE_OMIAI_CHANNEL_ID"]
      config.channel_secret = ENV['LINE_OMIAI_CHANNEL_SECRET']
      config.channel_token = ENV['LINE_OMIAI_CHANNEL_TOKEN']
    }
  end

  def push(text)
    message = {
      type: 'text',
      text: text
    }
    user_id = "Ub23b7ec6629c7e2a1d118dd91c6580a5"
    client.push_message(user_id, message)
    user_id2 = "Ue07aae93ae84358fdc8a100c0b889ea3"
    client.push_message(user_id2, message)
  end

  def callback
    @body = request.body.read
    @signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(@body, @signature)
      error 400 do
        'Bad Request'
      end
    end
    @line_header = {
      'Authorization' => "Bearer " + ENV['LINE_CHANNEL_TOKEN'],
      'Content-type' => 'application/json',
    }
    events = client.parse_events_from(@body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event['message']['text'] == "起動"
            push("「起動」が押された！")
            index
          end
          if event['message']['text'].include?("-")
            token = OmiaiToken.find_or_initialize_by(id: 1)
            token.update(token: event['message']['text'])
            push("アクセストークンを保存しました！")
          end
        end
      end
    end
  end

  def index
    begin
      push("足跡たくさんつけてきますね！")
      i = 0
      @token = OmiaiToken.find(1)
      @api_headers_recommend = {
        'accept' => '*/*',
        'Content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
        'accept-encoding' => 'gzip;q=1.0, compress;q=0.5',
        'User-agent' => 'Omiai/9.3.6 (iPhone; iOS 14.4; Scale/2.0)',
        'accept-language' => 'ja-JP;q=1.0',
        'content-length' => '71'
      }
      results_url = URI.parse('https://api2.omiai-jp.com/search/recommend/results')
      results_http = Net::HTTP.new(results_url.host, results_url.port)
      results_http.use_ssl = true
      loop do
        begin
          push("〜ちゃんと動作中〜")
          # 新規順を開く
          sleep rand(10..20)
          params_fresh = { omi_access_token: @token.token, action_code: 'view', screen_code: 'search_fresh' }
          html_post("https://api2.omiai-jp.com/logging/action", "95", params_fresh)
          # おすすめ順を開く
          sleep rand(10..20)
          params_search = { omi_access_token: @token.token, action_code: 'view', screen_code: 'search' }
          html_post("https://api2.omiai-jp.com/logging/action", "89", params_search)
          # ログイン順を一度リフレッシュ
          sleep rand(10..20)
          params_refresh = { omi_access_token: @token.token, limit: '48' }
          html_post("https://api2.omiai-jp.com/search/sort/login", "62", params_refresh)
          # ログイン順の結果を取得
          sleep rand(10..20)
          params_recommend = { omi_access_token: @token.token, limit: '48', offset: '1' }
          res = html_post('https://api2.omiai-jp.com/search/sort/login/results', "69", params_recommend)
          res_body = JSON.parse(res.body)
          if res_body['results']
            res_body['results'].each do |result|
              user_id = result['user_id']
              if OmiaiUser.exists?(user_id: user_id)
                p result['nickname'] + "さんは既に足跡をつけたユーザです。スルーします。"
              else
                OmiaiUser.create(user_id: user_id)
                params_footprint = { omi_access_token: @token.token, referer: 'SearchDetail', user_id: user_id }
                sleep rand(7..60)
                html_post("https://api2.omiai-jp.com/footprint/leave", "95", params_footprint)
                p result['nickname'] + "さんに足跡をつけました"
              end
            end
            # 成功したため、iを初期化する
            i = 0
          else
            if i < 10
              p "再検索します"
              p (i + 1).to_s + "回目の再検索です"
              i += 1
              sleep rand(20..30)
            else
              raise
            end
          end
        rescue
          # 6回連続で失敗した場合は終了
          if i < 10
            i += 1
            p (i + 1).to_s + "回目の処理失敗です"
            retry
          else
            p i.to_s + "回処理が失敗しました。プログラムを終了します。"
            push(i.to_s + "回処理が失敗しました。プログラムを終了します。")
            raise
          end
        end
      end
      render json: "終了"
    rescue
      p "====処理が中断されました===="
      push("現在処理が止まってるよ！アクセストークンの有効期限が終わったのかも！")
      return false
    end
  end

  def html_post(url, header_length, data)
    api_headers = {
      'accept' => '*/*',
      'Content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
      'accept-encoding' => 'gzip;q=1.0, compress;q=0.5',
      'User-agent' => 'Omiai/9.3.6 (iPhone; iOS 14.4; Scale/2.0)',
      'accept-language' => 'ja-JP;q=1.0',
      'content-length' => header_length
    }
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.path)
    req.set_form_data(data)
    req.initialize_http_header(api_headers)
    res = http.request(req)
    p res
    res
  end
end