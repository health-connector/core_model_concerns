module Behaviors
  module UnsetableSparseFields
    def unset_sparse(field)
      normalized = database_field_name(field)
      attributes.delete(normalized)
    end
  end
end
