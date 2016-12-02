module serialize.build;

import std.traits;

import serialize.write;
import serialize.read;
import serialize.types;

mixin template Serialize(T) //if(isStruct!T)
{
	enum __buildStr__ = _serializeFun!T();
	mixin(__buildStr__);

	pragma(inline)
	static ubyte[] serialize(Allocator = GCAllocator)(ref T value)
	{
		IWriteStream!(Allocator)  stream = IWriteStream!(Allocator)(32);
		serialize!Allocator(value,&stream);
		return stream.data();
	}

	pragma(inline)
	static T unsSerialize(ReadStream * stream)
	{
		T value;
		unSerialize(&value,stream);
		return value;
	}
}

string _serializeFun(T)() if(isStruct!T)
{
	string str = "static void serialize(Allocator = GCAllocator)(ref " ~ T.stringof ~ " value, IWriteStream!(Allocator) * stream){\n";
	str ~= "stream.startStruct();\n scope(success) stream.endStruct();\n";

	string  rstr = "static void unSerialize(" ~ T.stringof ~ " * value, ReadStream * stream){\n";
	rstr ~= "stream.startReadStruct();\n scope(success) stream.endReadStruct();\n";

	foreach(memberName; FieldNameTuple!T)
	{
		static if(isBasicSupport!(typeof(__traits(getMember,T, memberName))).isBSupport && !isCallable!(__traits(getMember,T, memberName)))
		{
			static if(isStruct!(typeof(__traits(getMember,T, memberName))))
			{
				static if(isArray!(typeof(__traits(getMember,T, memberName))))
				{
					str ~= writeStructArray!(typeof(__traits(getMember,T, memberName)),"value." ~ memberName)();
					rstr ~= readStructArray!(typeof(__traits(getMember,T, memberName)),"value." ~ memberName)();
				}
				else
				{
					str ~= typeof(__traits(getMember,T, memberName)).stringof ~ ".serialize!(Allocator)(value." ~ memberName ~ ", stream);\n";
					rstr ~= typeof(__traits(getMember,T, memberName)).stringof ~ ".unSerialize(&value." ~ memberName ~ ", stream);\n";
				}
			}
			else
			{
				str ~= "stream.write!(" ~ typeof(__traits(getMember,T, memberName)).stringof ~ ")(" ~ "value." ~ memberName ~ ");\n";
				rstr ~= "value." ~ memberName ~ " = stream.read!(" ~ typeof(__traits(getMember,T, memberName)).stringof ~ ")();\n";
			}
		}
	}
	str ~= "}\n";
	rstr ~= "}\n";
	return str ~ "\n" ~ rstr;
}

string writeStructArray(T,string memberName, int i = 0)()
{
	string str = "{stream.startArray!(";
	str ~= ForeachType!(T).stringof ~ ")();\n";
	str ~= "foreach(ref v"~ i.stringof ~" ; " ~ memberName ~ "){\n";
	static if(isArray!(ForeachType!T))
	{
		str ~= writeStructArray!(ForeachType!T,"v"~ i.stringof, i + 1)();
	}
	else
	{
		str ~= ForeachType!T.stringof ~ ".serialize!(Allocator)(v"~ i.stringof ~ " ,stream);\n";
	}
	str ~= "}\n";
	str ~= "stream.endArray();}\n";
	return str;
}

string readStructArray(T,string memberName, int i = 0)()
{
	string  str = "{/*writeln(\"read array in : "~ memberName ~"\");*/\n ";
	str ~= "uint leng" ~ i.stringof ~ " = stream.startReadArray();\n";
//	str ~= "writeln(\"======\");\n ";
	str ~= memberName ~ " = new " ~ ForeachType!T.stringof ~ "[leng" ~  i.stringof ~ "];\n";
	str ~= "foreach(v"~ i.stringof ~" ; 0..leng" ~ i.stringof ~ "){\n";
	static if(isArray!(ForeachType!T))
	{
		str ~= readStructArray!(ForeachType!T,memberName ~"[v"~ i.stringof ~ "]", i + 1)();
	}
	else
	{
		str ~= ForeachType!T.stringof ~ ".unSerialize(&"~memberName ~ "[v"~ i.stringof ~ "] , stream);\n";
		
	}
	str ~= "}\n";
	str ~= "stream.endReadArray();}\n";
	return str;
}