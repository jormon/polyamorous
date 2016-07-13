# active_record_5.1_ruby_2/join_dependency.rb

module Polyamorous
  module JoinDependencyExtensions

    # Replaces ActiveRecord::Associations::JoinDependency#build.
    #
    def build(associations, base_klass)
      associations.map do |name, right|
        if name.is_a? Join
          reflection = find_reflection base_klass, name.name
          reflection.check_validity!
          klass = if reflection.polymorphic?
            name.klass || base_klass
          else
            reflection.klass
          end
          JoinAssociation.new(reflection, build(right, klass), name.klass, name.type)
        else
          reflection = find_reflection base_klass, name
          reflection.check_validity!
          if reflection.polymorphic?
            raise ActiveRecord::EagerLoadPolymorphicError.new(reflection)
          end
          JoinAssociation.new reflection, build(right, reflection.klass)
        end
      end
    end

    def find_join_association_respecting_polymorphism(reflection, parent, klass)
      if association = parent.children.find { |j| j.reflection == reflection }
        unless reflection.polymorphic?
          association
        else
          association if association.base_klass == klass
        end
      end
    end

    def build_join_association_respecting_polymorphism(reflection, parent, klass)
      if reflection.polymorphic? && klass
        JoinAssociation.new(reflection, self, klass)
      else
        JoinAssociation.new(reflection, self)
      end
    end

    # Replaces ActiveRecord::Associations::JoinDependency#join_constraints.
    #
    # This internal method was changed in Rails 5.0 by commit
    # https://github.com/rails/rails/commit/e038975 which added
    # left_outer_joins (see #make_polyamorous_left_outer_joins below) and added
    # passing an additional argument, `join_type`, to #join_constraints.
    #
    def join_constraints(outer_joins, join_type)
      joins = join_root.children.flat_map { |child|
        if join_type == Arel::Nodes::OuterJoin
          make_polyamorous_left_outer_joins join_root, child
        else
          make_polyamorous_inner_joins join_root, child
        end
      }

      joins.concat outer_joins.flat_map { |oj|
        if join_root.match? oj.join_root
          walk(join_root, oj.join_root)
        else
          oj.join_root.children.flat_map { |child|
            make_outer_joins(oj.join_root, child)
          }
        end
      }
    end

    # Replaces ActiveRecord::Associations::JoinDependency#make_left_outer_joins,
    # a new method that was added in Rails 5.0 with the following commit:
    # https://github.com/rails/rails/commit/e038975
    #
    def make_polyamorous_left_outer_joins(parent, child)
      tables    = child.tables
      join_type = Arel::Nodes::OuterJoin
      info      = make_constraints parent, child, tables, join_type

      [info] + child.children.flat_map { |c|
        make_polyamorous_left_outer_joins(child, c)
      }
    end

    # Replaces ActiveRecord::Associations::JoinDependency#make_inner_joins.
    #
    def make_polyamorous_inner_joins(parent, child)
      tables    = child.tables
      join_type = child.join_type || Arel::Nodes::InnerJoin
      info      = make_constraints parent, child, tables, join_type

      [info] + child.children.flat_map { |c|
        make_polyamorous_inner_joins(child, c)
      }
    end

    private :make_polyamorous_inner_joins, :make_polyamorous_left_outer_joins

    module ClassMethods
      # Prepended before ActiveRecord::Associations::JoinDependency#walk_tree.
      #
      def walk_tree(associations, hash)
        if TreeNode === associations
          associations.add_to_tree(hash)
        else
          super(associations, hash)
        end
      end
    end

  end
end
