using System;
using System.Collections;

namespace Bon
{
	enum BonSerializeFlags : uint8
	{
		/// Include public fields, don't include default fields, respect attributes (default)
		case Default = 0;

		/// Include private fields
		case AllowNonPublic = 1;

		/// Whether or not to include fields default values (e.g. null, etc)
		case IncludeDefault = 1 << 1;

		/// Ignore field attributes (only recommended for debugging / complete structure dumping)
		case IgnoreAttributes = 1 << 2;

		/// The produced string will be formatted (and slightly more verbose) for manual editing.
		case Verbose = 1 << 3;
	}

	enum BonDeserializeFlags : uint8
	{
		/// Fully set the state of the target structure based on the given string.
		case Default = 0;

		// TODO
		/// Fields not mentioned in the given string will be left as they are
		/// instead of being nulled.
		case IgnoreUnmentionedFields = 1;
	}

	/// Defines the behavior of bon. May be modified globally (gBonEnv)
	/// or for some calls only be creating a BonEnvironment to modify
	/// and passing that to calls for use instead of the global fallback.
	class BonEnvironment
	{
		public BonSerializeFlags serializeFlags;
		public BonDeserializeFlags deserializeFlags;

		// TODO: put these into practise, iterate a bit, maybe write helper methods / mixins!
		public function void MakeThing(Span<uint8> into, Type allocType, Type onType);
		public function void DestroyThing(Variant thing, Type onType);

		// TODO
		// For custom handler registration
		// -> handler for custom serialize & deserialize

		/// When bon needs to allocate or deallocate a reference type, a handler is called for it when possible
		/// instead of allocating with new or deleting. This can be used to gain more control over the allocation
		/// or specific types, for example to reference existing ones or register allocated instances elsewhere
		/// as well.
		/// BON WILL CALL THESE INSTEAD OF ALLOCATING/DEALLOCATING AND TRUSTS THE USER TO MANAGE IT.
		///
		/// [!] As a special case, this is always called on StringView. If you want to deserialize it, you must
		///     provide a handler for it.
		public Dictionary<Type, (MakeThing make, DestroyThing destroy)> instanceHandlers = new .() ~ delete _;

		public this()
		{
			// TODO: copy global if set
		}

		// TODO methods for access?
	}

	static
	{
		public static BonEnvironment gBonEnv =
			{
				let env = new BonEnvironment();

				env
			} ~ delete _;
	}
}