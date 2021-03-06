class Api::V1::OmiaiController < ApplicationController
  require 'line/bot'
  require 'open-uri'
  # callbackアクションのCSRFトークン認証を無効
  protect_from_forgery :except => [:callback]
  # 足跡ツールline_botのクライアント
  def client_omiai_foot
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
    user_id = ENV['LINE_OMIAI_USER_1']
    client_omiai_foot.push_message(user_id, message)
    user_id2 = ENV['LINE_OMIAI_USER_2']
    client_omiai_foot.push_message(user_id2, message)
  end

  def callback
    @body = request.body.read
    @signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client_omiai_foot.validate_signature(@body, @signature)
      error 400 do
        'Bad Request'
      end
    end
    events = client_omiai_foot.parse_events_from(@body)
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
      i = 0
      loop do
        begin
          token = OmiaiToken.find(1)
          random_int = rand(1..10)
          push("〜ちゃんと動作中〜") if random_int == 1
          res = get_results(token)
          res_body = JSON.parse(res.body)
          if res_body['results']
            res_body['results'].each do |result|
              user_id = result['user_id']
              if OmiaiUser.exists?(user_id: user_id)
                p result['nickname'] + "さんは既に足跡をつけたユーザです。スルーします。"
              else
                OmiaiUser.create(user_id: user_id)
                params_footprint = { omi_access_token: token.token, referer: 'SearchDetail', user_id: user_id }
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
end