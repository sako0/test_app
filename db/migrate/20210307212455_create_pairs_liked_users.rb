class CreatePairsLikedUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :pairs_liked_users do |t|
      t.text :user_id
      t.timestamps
    end
  end
end
