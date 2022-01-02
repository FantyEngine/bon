using System;
using System.Diagnostics;
using System.Reflection;

namespace Bon.Integrated
{
	public enum BonSerializeFlags : uint8
	{
		public static Self DefaultFlags = Default;

		/// Include public fields, don't include default fields, respect attributes (default)
		case Default = 0;

		/// Include private fields
		case AllowNonPublic = 1;

		/// Whether or not to include fields default values (e.g. null, etc)
		case IncludeDefault = 1 << 1;

		/// Ignore field attributes (only recommended for debugging / complete structure dumping)
		case IgnoreAttributes = 1 << 2;

		/// The produced string will be suitable (and slightly more verbose) for manual editing.
		case Verbose = 1 << 3;
	}

	static class Serialize
	{
		static mixin VariantDataIsZero(Variant val)
		{
			bool isZero = true;
			for (var i < val.VariantType.Size)
				if (((uint8*)val.DataPtr)[i] != 0)
					isZero = false;
			isZero
		}

		static mixin DoInclude(ref Variant val, BonSerializeFlags flags)
		{
			(flags.HasFlag(.IncludeDefault) || !VariantDataIsZero!(val))
		}

		static mixin DoTypeOneLine(Type type, BonSerializeFlags flags)
		{
			(type.IsPrimitive || (type.IsTypedPrimitive && (!flags.HasFlag(.Verbose) || !type.IsEnum)))
		}

		[Inline]
		public static void Thing(BonWriter writer, ref Variant thingVal, BonSerializeFlags flags = .DefaultFlags)
		{
			if (DoInclude!(ref thingVal, flags))
				Value(writer, ref thingVal, flags);
		}

		public static void Value(BonWriter writer, ref Variant val, BonSerializeFlags flags = .DefaultFlags, bool doOneLine = false)
		{
			let valType = val.VariantType;

			// Make sure that doOneLineVal is only passed when valid
			Debug.Assert(!doOneLine || DoTypeOneLine!(valType, flags));

			mixin AsThingToString<T>()
			{
				T thing = *(T*)val.DataPtr;
				thing.ToString(writer.outStr);
			}

			mixin Integer(Type type)
			{
				switch (type)
				{
				case typeof(int8): AsThingToString!<int8>();
				case typeof(int16): AsThingToString!<int16>();
				case typeof(int32): AsThingToString!<int32>();
				case typeof(int64): AsThingToString!<int64>();
				case typeof(int): AsThingToString!<int>();

				case typeof(uint8): AsThingToString!<uint8>();
				case typeof(uint16): AsThingToString!<uint16>();
				case typeof(uint32): AsThingToString!<uint32>();
				case typeof(uint64): AsThingToString!<uint64>();
				case typeof(uint): AsThingToString!<uint>();

				default: Debug.FatalError(); // Should be unreachable
				}
			}

			mixin Char(Type type)
			{
				char32 char = 0;
				switch (type)
				{
				case typeof(char8): char = (.)*(char8*)val.DataPtr;
				case typeof(char16): char = (.)*(char16*)val.DataPtr;
				case typeof(char32): char = *(char32*)val.DataPtr;
				}
				writer.Char(char);
			}

			mixin Float(Type type)
			{
				switch (type)
				{
				case typeof(float): AsThingToString!<float>();
				case typeof(double): AsThingToString!<double>();

				default: Debug.FatalError(); // Should be unreachable
				}
			}

			mixin Bool()
			{
				bool boolean = *(bool*)val.DataPtr;
				if (flags.HasFlag(.Verbose))
					boolean.ToString(writer.outStr);
				else (boolean ? 1 : 0).ToString(writer.outStr);
			}

			writer.EntryStart(doOneLine);

			if (valType.IsPrimitive)
			{
				if (valType.IsInteger)
					Integer!(valType);
				else if (valType.IsFloatingPoint)
					Float!(valType);
				else if (valType.IsChar)
					Char!(valType);
				else if (valType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsTypedPrimitive)
			{
				if (valType.UnderlyingType.IsInteger)
				{
					if (valType.IsEnum && flags.HasFlag(.Verbose))
					{
						int64 value = 0;
						Span<uint8>((uint8*)val.DataPtr, valType.Size).CopyTo(Span<uint8>((uint8*)&value, valType.Size));

						bool found = false;
						for (var field in valType.GetFields())
						{
							if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase) &&
								*(int64*)&field.[Friend]mFieldData.[Friend]mData == value)
							{
								writer.Enum(field.Name);
								found = true;
								break;
							}
						}

						if (!found)
						{
							// There is no exact named value here, but maybe multiple!

							// We only try once, but that's better than none. If you were
							// to have this enum { A = 0b0011, B = 0b0111, C = 0b1100 }
							// and run this on 0b1111, this algorithm would fail to
							// identify .A | .C, but rather .B | 0b1000 because it takes
							// the largest match first and never looks back if it doesn't
							// work out. The easiest way to make something more complicated
							// work would probably be recursion... maybe in the future
							int64 valueLeft = value;
							String bestValName = scope .();
							while (valueLeft != 0)
							{
								// Go through all values and find best match in therms of bits
								int64 bestVal = 0;
								var bestValBits = 0;
								bool foundAny = false;
								for (var field in valType.GetFields())
								{
									if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase))
									{
										let fieldVal = *(int64*)&field.[Friend]mFieldData.[Friend]mData;

										if (fieldVal == 0 || (fieldVal & ~valueLeft) != 0)
											continue; // fieldVal contains bits that valueLeft doesn't have

										var bits = 0;
										for (let i < sizeof(int64) * 8)
											if (((fieldVal >> i) & 0b1) != 0)
												bits++;

										if (bits > bestValBits)
										{
											bestVal = fieldVal;
											bestValName.Set(field.Name);
											bestValBits = bits;
										}
									}
								}

								if (bestValBits > 0)
								{
									valueLeft &= ~bestVal; // Remove all bits it shares with this
									writer.Enum(bestValName);
									foundAny = true;
								}
								else
								{
									if (foundAny)
										writer.EnumAdd();
									Integer!(valType.UnderlyingType);
									break;
								}

								if (valueLeft == 0)
									break;
							}
						}
					}
					else Integer!(valType.UnderlyingType);
				}
				else if (valType.UnderlyingType.IsFloatingPoint)
					Float!(valType.UnderlyingType);
				else if (valType.UnderlyingType.IsChar)
					Char!(valType.UnderlyingType);
				else if (valType.UnderlyingType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsStruct)
			{
				if (valType == typeof(StringView))
				{
					let view = val.Get<StringView>();

					if (view.Ptr == null)
						writer.Null();
					else writer.String(view);
				}
				else if (valType.IsEnum && valType.IsUnion)
				{
					// Enum union in memory:
					// {<payload>|<discriminator>}

					bool didWrite = false;
					uint64 unionCaseIndex = uint64.MaxValue;
					uint64 currCaseIndex = 0;
					for (var enumField in valType.GetFields())
					{
						if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumDiscriminator))
						{
							let discrType = enumField.FieldType;
							var discrVal = Variant.CreateReference(discrType, (uint8*)val.DataPtr + enumField.[Friend]mFieldData.mData);
							Debug.Assert(discrType.IsInteger);

							mixin GetVal<T>() where T : var
							{
								T thing = *(T*)discrVal.DataPtr;
								unionCaseIndex = (uint64)thing;
							}

							switch (discrType)
							{
							case typeof(int8): GetVal!<int8>();
							case typeof(int16): GetVal!<int16>();
							case typeof(int32): GetVal!<int32>();
							case typeof(int64): GetVal!<int64>();
							case typeof(int): GetVal!<int>();

							case typeof(uint8): GetVal!<uint8>();
							case typeof(uint16): GetVal!<uint16>();
							case typeof(uint32): GetVal!<uint32>();
							case typeof(uint64): GetVal!<uint64>();
							case typeof(uint): GetVal!<uint>();

							default: Debug.FatalError(); // Should be unreachable
							}
						}
						else if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumCase)) // Filter through unioncaseIndex
						{
							Debug.Assert(unionCaseIndex != uint64.MaxValue);

							// Skip enum cases until we get to the selected one
							if (currCaseIndex != unionCaseIndex)
							{
								currCaseIndex++;
								continue;
							}

							var unionPayload = Variant.CreateReference(enumField.FieldType, val.DataPtr);

							// Do serialize of discriminator and payload
							writer.Enum(enumField.Name);
							Struct(writer, ref unionPayload, flags);

							didWrite = true;
							break;
						}
					}

					Debug.Assert(didWrite);
				}
				else Struct(writer, ref val, flags);
			}
			else if (valType is SizedArrayType)
			{
				let t = (SizedArrayType)valType;
				let count = t.ElementCount;
				if (count > 0)
				{
					// Since this is a fixed-size array, this info is not necessary to
					// deserialize in any case. But it's nice for manual editing to know how
					// much the array can hold
					if (flags.HasFlag(.Verbose))
						writer.Sizer(count, true);
					
					let arrType = t.UnderlyingType;
					let doArrayOneLine = DoTypeOneLine!(arrType, flags);
					using (writer.ArrayBlock(doArrayOneLine))
					{
						var includeCount = count;
						if (!flags.HasFlag(.IncludeDefault))
						{
							var ptr = (uint8*)val.DataPtr + arrType.Stride * (count - 1);
							for (var i = count - 1; i >= 0; i--)
							{
								var arrVal = Variant.CreateReference(arrType, ptr);

								// If this gets included, we'll have to include everything until here!
								if (DoInclude!(ref arrVal, flags))
								{
									includeCount = i + 1;
									break;
								}

								ptr -= arrType.Stride;
							}
						}

						var ptr = (uint8*)val.DataPtr;
						for (let i < includeCount)
						{
							var arrVal = Variant.CreateReference(arrType, ptr);
							Value(writer, ref arrVal, flags, doArrayOneLine);

							ptr += arrType.Stride;
						}
					}
				}
			}
			else if (valType.IsObject)
			{
				if (valType == typeof(String))
				{
					let str = val.Get<String>();

					if (str == null)
						writer.Null();
					else writer.String(str);
				}
				else Debug.FatalError(); // TODO
			}
			else if (valType.IsPointer)
			{
				Debug.FatalError(); // TODO
			}
			else Debug.FatalError();

			writer.EntryEnd(doOneLine);
		}

		public static void Struct(BonWriter writer, ref Variant structVal, BonSerializeFlags flags = .DefaultFlags)
		{
			let structType = structVal.VariantType;

			Debug.Assert(structType.IsStruct);

			bool hasUnnamedMembers = false;
			using (writer.ObjectBlock())
			{
				if (structType.FieldCount > 0)
				{
					for (let m in structType.GetFields(.Instance))
					{
						if ((!flags.HasFlag(.IgnoreAttributes) && m.GetCustomAttribute<NoSerializeAttribute>() case .Ok) // check hidden
							|| !flags.HasFlag(.AllowNonPublic) && (m.[Friend]mFieldData.mFlags & .Public == 0) // check protection level
							&& (flags.HasFlag(.IgnoreAttributes) || !(m.GetCustomAttribute<DoSerializeAttribute>() case .Ok))) // check if we still include it anyway
							continue;

						Variant val = Variant.CreateReference(m.FieldType, ((uint8*)structVal.DataPtr) + m.MemberOffset);

						if (!DoInclude!(ref val, flags))
							continue;

						if (flags.HasFlag(.Verbose) && uint64.Parse(m.Name) case .Ok)
							hasUnnamedMembers = true;

						writer.Identifier(m.Name);
						Value(writer, ref val, flags);
					}
				}
			}
			
			if (flags.HasFlag(.Verbose))
			{
				// Just add this as a comment in case anyone wonders...
				if (!structType is TypeInstance)
					writer.outStr.Append(scope $"/* No reflection data for {structType}. Add [Serializable] or force it */");
				else if (hasUnnamedMembers)
					writer.outStr.Append(scope $"/* Type has unnamed members */");
			}
		}
	}
}