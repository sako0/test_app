class Api::V1::PairsLikeController < ApplicationController
  # callbackアクションのCSRFトークン認証を無効
  protect_from_forgery :except => [:callback]
  # 足跡ツールline_botのクライアント
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_id = ENV["LINE_PAIRS_SUGGEST_ID"]
      config.channel_secret = ENV['LINE_PAIRS_SUGGEST_SECRET']
      config.channel_token = ENV['LINE_PAIRS_SUGGEST_TOKEN']
    }
  end

  def push(text)
    message = {
      type: 'text',
      text: text
    }
    user_id = ENV['LINE_PAIRS_SUGGEST_USER_1']
    client.push_message(user_id, message)
    user_id2 = ENV['LINE_PAIRS_SUGGEST_USER_2']
    client.push_message(user_id2, message)
  end

  def push_image(url, item, sim, file_name)
    if item['partner']['residence_state_id'] == 13
      @area = "東京"
    elsif item['partner']['residence_state_id'] == 11
      @area = "埼玉"
    else
      @area = "その他"
    end
    like_data = { method: "like", user_id: item["partner"]["id"].to_s, user_name: item["partner"]['nickname'], file_name: file_name }.to_json
    delete_data = { method: "delete", user_id: item["partner"]["id"].to_s, user_name: item["partner"]['nickname'], file_name: file_name }.to_json
    message = {
      "type": "template",
      "altText": "This is a buttons template",
      "template": {
        "type": "buttons",
        "thumbnailImageUrl": url,
        "imageAspectRatio": "rectangle",
        "imageSize": "cover",
        "imageBackgroundColor": "#FFFFFF",
        "title": item['partner']['nickname'],
        "text": item['partner']['age'].to_s + "歳 / " + @area + " / " + sim + "%マッチ",
        "defaultAction": {
          "type": "uri",
          "label": "View detail",
          "uri": url
        },
        "actions": [
          {
            "type": "postback",
            "label": "いいね！",
            "data": like_data
          },
          {
            "type": "postback",
            "label": "画像削除",
            "data": delete_data
          },
          {
            "type": "uri",
            "label": "詳細（未実装）",
            "uri": url
          }
        ]
      }
    }
    user_id = ENV['LINE_PAIRS_SUGGEST_USER_1']
    client.push_message(user_id, message)
    user_id2 = ENV['LINE_PAIRS_SUGGEST_USER_2']
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
          if event['message']['text'].length == 40
            token = PairsToken.find_or_initialize_by(id: 1)
            if token.token == event['message']['text']
              push("既に同じアクセストークンが保存されています")
            else
              token.update(token: event['message']['text'])
              push("アクセストークンを保存しました！")
            end
          end
        end
      when Line::Bot::Event::Postback
        if event['postback']['data']
          object = JSON.load(event['postback']['data'])
          if object['method'] == "like"
            like_user(object['user_id'])
          elsif object['method'] == "delete"
            object_delete(object['file_name'])
          else
            push "何した？"
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
          action_log
          res_body = get_results
          if res_body['layouts'][1]['chunk']['items']
            p res_body['layouts'][0]
            res_body['layouts'][1]['chunk']['items'].each_with_index do |item, index|
              if index != 2
                user_id = item['partner']['id']
                if PairsLikedUser.exists?(user_id: user_id)
                  p item['partner']['nickname'] + "さんは既に画像判定をしたユーザです。スルーします。"
                else
                  PairsLikedUser.create(user_id: user_id)
                  image_url = item['partner']['images'][0]['url']
                  p image_url
                  file_name = get_image(image_url, user_id)
                  object_uploaded(file_name)
                  similar = compare_images(file_name, "target1.jpg")
                  if similar > 20
                    similar_i = similar.to_i
                    similar_s = similar_i.to_s
                    s3_url = get_object_url(file_name)
                    push_image(s3_url, item, similar_s, file_name)
                    p item['partner']['nickname'] + "さんの情報をLINEに送信しました"
                  else
                    p item['partner']['nickname'] + "さんは似ていません。スルーします。"
                    object_delete(file_name)
                  end
                end
              end
            end
            #成功したため、iを初期化する
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
    rescue
      p "====処理が中断されました===="
      push("現在処理が止まってるよ！アクセストークンの有効期限が終わったのかも！")
      return false
    end
  end

  def get_results
    sleep 1
    res = pairs_get("https://pairs.lv/2.0/search/layout?limit=5&offset=0")
    p res
    res
  end

  def action_log
    sleep 1
    params_action_log_1 = {
      action_group: "search_feature", view: "grid:2", action_log_code: 0, action_id: " " }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "85", params_action_log_1)
    sleep 1
    params_action_log_2 = { action_id: ' ', action_log_code: 0, action_group: 'search_feature', view: 'grid:2' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "85", params_action_log_2)
    sleep 1
    params_action_log_3 = { action_id: ' ', action_group: 'search_feature', action_log_code: 0, view: 'grid:2' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "85", params_action_log_3)
    sleep 1
    params_action_log_4 = { action_log_code: 0, other_params: { relation_code: 'wow' }, action_id: 'search_feature_scroll', view: 'grid:5', action_group: 'search_feature' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "144", params_action_log_4)
    sleep 1
    params_action_log_5 = { action_log_code: 0, other_params: { relation_code: 'wow' }, action_id: 'search_feature_scroll', view: 'grid:2', action_group: 'search_feature' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "144", params_action_log_5)
    sleep 1
    params_action_log_6 = { action_log_code: 0, other_params: { relation_code: 'wow' }, action_id: 'search_feature_scroll', view: 'grid:4', action_group: 'search_feature' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "144", params_action_log_6)
    sleep 1
    params_action_log_7 = { action_log_code: 0, other_params: { relation_code: 'wow' }, action_id: 'search_feature_scroll', view: 'grid:1', action_group: 'search_feature' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "144", params_action_log_7)
    sleep 1
    params_action_log_8 = { action_log_code: 0, other_params: { relation_code: 'wow' }, action_id: 'search_feature_scroll', view: 'grid:3', action_group: 'search_feature' }.to_json
    pairs_post("https://pairs.lv/1.0/action_log", "144", params_action_log_8)
  end

  def like_user(user_id)
    params = { source: 'search~chunk_chunk-grid::personal' }.to_json
    url = "https://pairs.lv/2.0/user_like/" + user_id
    pairs_post(url, "46", params)
  end
end
