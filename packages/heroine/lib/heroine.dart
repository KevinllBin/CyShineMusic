/*
MIT License

Copyright (c) 2024 Tim Lehmann for whynotmake.it

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/// An evolution on Heroes in Flutter, supporting Spring-based animations as
/// well as cleaner route transitions.
library heroine;

export 'package:motor/motor.dart'
    show
        CupertinoMotion,
        CurvedMotion,
        MaterialSpringMotion,
        Motion,
        SpringMotion;

export 'src/drag_dismissable.dart' show DragDismissable;
export 'src/heroine_route_mixin.dart'
    show HeroinePageRoute, HeroinePageRouteMixin, ReactToHeroineDismiss;
export 'src/heroine_velocity.dart' show HeroineVelocity;
export 'src/heroines.dart'
    show
        DuplicateHeroinePolicy,
        Heroine,
        HeroineController,
        HeroineMode,
        HeroineTransitionDetails;
export 'src/shuttle_builders.dart';
