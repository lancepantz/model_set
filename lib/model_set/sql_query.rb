class ModelSet
  class SQLQuery < SQLBaseQuery
    include Conditioned

    def anchor!(query, opts = {})
      if @limit_fetch = opts[:limit_fetch]
        @reorder = query.ids
      else
        if query.respond_to?(:sql)
          sql = "#{id_field_with_prefix} IN (#{query.sql})"
        else
          sql = ids_clause(query.ids)
          @reorder = query.ids
        end
        add_conditions!(sql)
      end
    end

    def ids
      if @ids.nil?
        if @limit_fetch
          base_conditions = conditions
          @ids = [].to_ordered_set
          @reorder.each_slice(@limit_fetch) do |ids|
            self.conditions = Conditions.new(:and, ids_clause(ids), *base_conditions)
            @ids.concat fetch_id_set(sql)
            if limit and @ids.size >= limit
              @ids.reorder!(@reorder).limit!(limit)
              break
            end
          end
          self.conditions = base_conditions
        else
          @ids = fetch_id_set(sql)
          @ids.reorder!(@reorder) if @reorder
        end
      end
      @ids
    end

    def limit_enabled?
      return true  if @limit_fetch
      return false if @reorder
      super
    end

    def aggregate(query, opts = {})
      sql = "SELECT #{query} #{from_clause}"
      sql << " LIMIT #{opts[:limit]}"       if opts[:limit]
      sql << " GROUP BY #{opts[:group_by]}" if opts[:group_by]
      result = db.select_rows(sql).first
      result.size == 1 ? result.first : result
    end

    def add_joins!(*joins)
      @joins ||= []

      joins.each do |join|
        @joins << sanitize_condition(join)
      end
      @joins.uniq!

      clear_cache!
    end

    def in!(ids, field = id_field_with_prefix)
      add_conditions!( ids_clause(ids, field) )
    end

    def order_by!(*args)
      opts = args.last.kind_of?(Hash) ? args.pop : {}

      @sort_join  = sanitize_condition(opts[:join])
      @sort_order = args
      @reorder    = nil
      clear_cache!
    end

    def reverse!
      if @reorder
        @reorder.reverse!
      elsif @sort_order
        @sort_order.collect! do |sub_order|
          if sub_order =~ / DESC$/i
            sub_order.slice(0..-6)
          else
            "#{sub_order} DESC"
          end
        end
      else
        @sort_order = ["#{id_field_with_prefix} DESC"]
      end
      clear_cache!
    end

    def sql
      "#{select_clause} #{from_clause} #{order_clause} #{limit_clause}"
    end

    def count
      @count ||= limit ? aggregate("COUNT(DISTINCT #{id_field_with_prefix})").to_i : size
    end

  private

    def select_clause
      "SELECT #{id_field_with_prefix}"
    end

    def from_clause
      "FROM #{table_name} #{join_clause} WHERE #{conditions.to_s}"
    end

    def order_clause
      return unless @sort_order
      # Prevent SQL injection attacks.
      "ORDER BY #{@sort_order.join(', ').gsub(/[^\w_, \.\(\)'\"]/, '')}"
    end

    def join_clause
      return unless @joins or @sort_join
      joins = []
      joins << @joins      if @joins
      joins << @sort_join if @sort_join
      joins.join(' ')
    end
  end
end
