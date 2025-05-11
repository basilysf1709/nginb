counter = 0

request = function()
   return wrk.format()
end

response = function(status, headers, body)
   if status ~= 200 then
      counter = counter + 1
   end
end

done = function()
   print(string.format("Non-200 responses: %d", counter))
end