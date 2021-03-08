class CreatePairsTokens < ActiveRecord::Migration[6.1]
  def change
    create_table :pairs_tokens do |t|
      t.text :token
      t.timestamps
    end
  end
end
