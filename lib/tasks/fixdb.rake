
desc "Fix all"
task :fixall => [:environment, "fixdb:openid", "fixdb:counters", "fixdb:votes", "fixdb:sync_counts", "fixdb:groups"] do
end

namespace :fixdb do
  task :openid => [:environment] do
    User.find_each do |user|
      next if user.identity_url.blank?

      puts "Updating: #{user.login}"
      user.push_uniq(:auth_keys => "open_id_#{user[:identity_url]}")
      user.unset(:identity_url => 1)
    end
  end

  task :sync_counts => [:environment] do
    Comment.find_each do |c|
      votes_average=0
      c.votes.each {|e| votes_average+=e.value }
      c.set("votes_count" => c.votes.size, "votes_average" => votes_average)
      if c.respond_to?(:flags)
        c.set("flags_count" => c.flags.size)
      end
    end

    Question.find_each do |q|
      votes_average=0
      q.votes.each {|e| votes_average+=e.value }
      q.set("flags_count" => q.flags.size, "votes_count" => q.votes.size, "votes_average" => votes_average)
    end
  end

  task :counters => :environment do
    Question.find_each do |q|
      q.set(:close_requests_count => q.close_requests.size)
      q.set(:open_requests_count => q.open_requests.size)
    end
  end

  task :votes => [:environment] do
    Group.find_each do |group|
      count = 0

      comments = MongoMapper.database.collection("comments")
      questions = MongoMapper.database.collection("questions")
      MongoMapper.database.collection("votes").find({:group_id => group["_id"]}).each do |vote|
        vote.delete("group_id")
        id = vote.delete("voteable_id")
        klass = vote.delete("voteable_type")
        collection = comments
        if klass == "Question"
          collection = questions;
        end
        count += 1
        collection.update({:_id => id}, "$addToSet" => {:votes => vote})
      end
      if count > 0
        puts "Updated #{count} #{group["name"]} votes "
      end
    end
    MongoMapper.database.collection("votes").drop
  end

  task :groups => [:environment] do
    Group.find_each(:language => [nil, '', 'none']) do |group|
      lang = group.description.to_s.language
      puts "Updating #{group.name} subdomain='#{group.subdomain}' detected as: #{lang}"

      group.language = (lang == :spanish) ? 'es' : 'en'
      group.languages = DEFAULT_USER_LANGUAGES
      if group.valid?
        group.save
      else
        puts "Invalid group: #{group.errors.full_messages}"
      end
    end
  end

  task :relocate => [:environment] do
    doc = JSON.parse(File.read('countries/all.json'))
    i=0
    doc.keys.each do |key|
      User.all({ :country_name => key}).each do |u|
        p "#{u.login}: before: #{u.country_name}, after: #{doc[key]["address"]["country"]}"
        lat = doc[key]["lat"]
        lon = doc[key]["lon"]
        User.set({:id => u.id},
                    {:position => GeoPosition.new(lat, lon),
                      :address => doc[key]["address"]})
        Comment.set({:user_id => u.id},
                    {:position => GeoPosition.new(lat, lon),
                      :address => doc[key]["address"]})
        Question.set({:user_id => u.id},
                    {:position => GeoPosition.new(lat, lon),
                      :address => doc[key]["address"]})
        Answer.set({:user_id => u.id},
                    {:position => GeoPosition.new(lat, lon),
                      :address => doc[key]["address"]})
      end
    end
  end

end
